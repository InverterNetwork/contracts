// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IERC20PaymentClientBase_v2,
    IPaymentProcessor_v2
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {
    ERC20PaymentClientBase_v2,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {ILM_PC_Lending_Facility_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_Lending_Facility_v1.sol";
import {IFundingManager_v1} from
    "src/modules/fundingManager/IFundingManager_v1.sol";
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IDynamicFeeCalculator_v1} from
    "@ex/fees/interfaces/IDynamicFeeCalculator_v1.sol";
import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {PackedSegmentLib} from
    "src/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title   House Protocol Lending Facility Logic Module
 *
 * @notice  A lending facility that allows users to borrow collateral tokens against issuance tokens.
 *          The system uses dynamic fee calculation based on liquidity rates and enforces borrowing limits.
 *          Each loan is tracked individually with a unique ID to handle floor price changes properly.
 *
 * @dev     This contract implements the following key functionality:
 *          - Borrowing collateral tokens against locked issuance tokens
 *          - Dynamic fee calculation based on floor liquidity rate
 *          - Repayment functionality with issuance token unlocking
 *          - Configurable borrowing limits and quotas
 *          - Role-based access control for facility management
 *          - Individual loan tracking with unique IDs for proper floor price handling
 *
 * @custom:setup    This module requires the following MANDATORY setup steps:
 *
 *                  1. Configure LENDING_FACILITY_MANAGER_ROLE:
 *                     - Purpose: Implements access control for managing the lending facility
 *                               parameters (borrowable quota, individual limits, etc.)
 *                     - How:     The OrchestratorAdmin must:
 *                               1. Retrieve the lending facility manager role identifier
 *                               2. Grant the role to designated admins
 *                     - Example: module.grantModuleRole(
 *                                 module.LENDING_FACILITY_MANAGER_ROLE(),
 *                                 adminAddress
 *                               );
 *
 *                  2. Initialize Lending Facility Parameters:
 *                     - Purpose: Sets up the lending facility parameters
 *                     - How:     A user with LENDING_FACILITY_MANAGER_ROLE must call:
 *                               1. setBorrowableQuota()
 *                               2. setDynamicFeeCalculator()
 *
 * @custom:upgrades This contract is upgradeable and uses the Inverter upgrade pattern.
 *                  The contract inherits from ERC20PaymentClientBase_v2 which provides
 *                  upgradeability through the Inverter proxy system. Upgrades should be
 *                  carefully tested to ensure no state corruption and proper initialization
 *                  of new functionality. The storage gap pattern is used to reserve space
 *                  for future upgrades.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
contract LM_PC_Lending_Facility_v1 is
    ILM_PC_Lending_Facility_v1,
    ERC20PaymentClientBase_v2
{
    // =========================================================================
    // Libraries

    using SafeERC20 for IERC20;

    // =========================================================================
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v2)
        returns (bool)
    {
        return interfaceId_ == type(ILM_PC_Lending_Facility_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @notice Maximum borrowable quota percentage (100%)
    uint internal constant _MAX_BORROWABLE_QUOTA = 10_000; // 100% in basis points

    //--------------------------------------------------------------------------
    // State

    /// @dev The role that allows managing the lending facility parameters
    bytes32 public constant LENDING_FACILITY_MANAGER_ROLE =
        "LENDING_FACILITY_MANAGER";

    /// @notice Borrowable Quota as percentage of Borrow Capacity (in basis points)
    uint public borrowableQuota;

    /// @notice Maximum leverage allowed for buyAndBorrow operations
    uint public maxLeverage;

    /// @notice Currently borrowed amount across all users
    uint public currentlyBorrowedAmount;

    /// @notice Next loan ID counter
    uint public nextLoanId;

    /// @notice Mapping of user addresses to their locked issuance token amounts
    mapping(address user => uint amount) internal _lockedIssuanceTokens;

    /// @notice Mapping of loan ID to loan details
    mapping(uint loanId => Loan loan) internal _loans;

    /// @notice Mapping of user addresses to their active loan IDs
    mapping(address user => uint[] loanIds) internal _userLoans;

    /// @notice Mapping of user addresses to their total outstanding loan principals (sum of all active loans)
    mapping(address user => uint amount) internal _userTotalOutstandingLoans;

    /// @notice Collateral token (the token being borrowed)
    IERC20 internal _collateralToken;

    /// @notice Issuance token (the token being locked as collateral)
    IERC20 internal _issuanceToken;

    /// @notice DBC FM address for floor price calculations
    address internal _dbcFmAddress;

    /// @notice Address of the Dynamic Fee Calculator contract
    address internal _dynamicFeeCalculator;

    /// @notice Storage gap for future upgrades
    uint[50] private __gap;

    // =========================================================================
    // Modifiers

    modifier onlyLendingFacilityManager() {
        _checkRoleModifier(LENDING_FACILITY_MANAGER_ROLE, _msgSender());
        _;
    }

    modifier onlyValidBorrowAmount(uint amount_) {
        _ensureValidBorrowAmount(amount_);
        _;
    }

    modifier onlyValidLoanId(uint loanId_) {
        if (
            !_loans[loanId_].isActive
                || _loans[loanId_].borrower != _msgSender()
        ) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidLoanId();
        }
        _;
    }

    // =========================================================================
    // Constructor & Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        // Decode module specific init data
        (
            address collateralToken,
            address issuanceToken,
            address dbcFmAddress,
            address dynamicFeeCalculator,
            uint borrowableQuota_,
            uint maxLeverage_
        ) = abi.decode(
            configData_, (address, address, address, address, uint, uint)
        );

        // Set init state
        _collateralToken = IERC20(collateralToken);
        _issuanceToken = IERC20(issuanceToken);
        _dbcFmAddress = dbcFmAddress;
        _dynamicFeeCalculator = dynamicFeeCalculator;
        borrowableQuota = borrowableQuota_;
        maxLeverage = maxLeverage_;
        nextLoanId = 1; // Start loan IDs from 1
    }

    // =========================================================================
    // Public - Mutating

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function borrow(uint requestedLoanAmount_)
        external
        virtual
        onlyValidBorrowAmount(requestedLoanAmount_)
        returns (uint loanId_)
    {
        return _borrow(requestedLoanAmount_, _msgSender(), _msgSender());
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function borrowFor(address receiver_, uint requestedLoanAmount_)
        external
        virtual
        onlyValidBorrowAmount(requestedLoanAmount_)
        returns (uint loanId_)
    {
        if (receiver_ == address(0)) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidReceiver();
        }
        return _borrow(requestedLoanAmount_, receiver_, receiver_);
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function repay(uint loanId_, uint repaymentAmount_)
        external
        onlyValidLoanId(loanId_)
    {
        address user = _msgSender();
        Loan storage loan = _loans[loanId_];

        if (repaymentAmount_ == 0 || repaymentAmount_ > loan.remainingPrincipal)
        {
            repaymentAmount_ = loan.remainingPrincipal;
        }

        // Calculate issuance tokens to unlock for this specific loan
        uint issuanceTokensToUnlock =
            _calculateIssuanceTokensToUnlockForLoan(loan, repaymentAmount_);

        // Update loan state
        loan.remainingPrincipal -= repaymentAmount_;

        // If loan is fully repaid, mark as inactive
        if (loan.remainingPrincipal == 0) {
            loan.isActive = false;
            // Remove from user's active loans
            _removeLoanFromUserLoans(user, loanId_);
        }

        // Unlock issuance tokens for this loan
        if (issuanceTokensToUnlock > 0) {
            _lockedIssuanceTokens[user] -= issuanceTokensToUnlock;
            _issuanceToken.safeTransfer(user, issuanceTokensToUnlock);
        }

        // Update global state
        _userTotalOutstandingLoans[user] -= repaymentAmount_;
        currentlyBorrowedAmount -= repaymentAmount_;

        // Transfer collateral back to DBC FM
        _collateralToken.safeTransferFrom(user, _dbcFmAddress, repaymentAmount_);

        // Emit events
        emit LoanRepaid(loanId_, user, repaymentAmount_, issuanceTokensToUnlock);
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function buyAndBorrow(uint amount_, uint leverage_)
        external
        virtual
        returns (uint loanId_)
    {
        return _buyAndBorrow(amount_, leverage_, _msgSender());
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function buyAndBorrowFor(address receiver_, uint amount_, uint leverage_)
        external
        virtual
        returns (uint loanId_)
    {
        if (receiver_ == address(0)) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidReceiver();
        }
        return _buyAndBorrow(amount_, leverage_, receiver_);
    }

    // =========================================================================
    // Public - Configuration (Lending Facility Manager only)

    /// @notice Set the borrowable quota
    /// @param newBorrowableQuota_ The new borrowable quota (in basis points)
    function setBorrowableQuota(uint newBorrowableQuota_)
        external
        onlyLendingFacilityManager
    {
        if (newBorrowableQuota_ > _MAX_BORROWABLE_QUOTA) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_BorrowableQuotaTooHigh();
        }
        borrowableQuota = newBorrowableQuota_;
        emit BorrowableQuotaUpdated(newBorrowableQuota_);
    }

    /// @notice Set the Dynamic Fee Calculator address
    /// @param newFeeCalculator_ The new fee calculator address
    function setDynamicFeeCalculator(address newFeeCalculator_)
        external
        onlyLendingFacilityManager
    {
        if (newFeeCalculator_ == address(0)) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidFeeCalculatorAddress();
        }
        _dynamicFeeCalculator = newFeeCalculator_;
        emit DynamicFeeCalculatorUpdated(newFeeCalculator_);
    }

    /// @notice Set the maximum leverage allowed for buyAndBorrow operations
    /// @param newMaxLeverage_ The new maximum leverage (must be >= 1)
    function setMaxLeverage(uint newMaxLeverage_)
        external
        onlyLendingFacilityManager
    {
        if (newMaxLeverage_ < 1 || newMaxLeverage_ > type(uint8).max) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidLeverage();
        }
        maxLeverage = newMaxLeverage_;
        emit MaxLeverageUpdated(newMaxLeverage_);
    }

    // =========================================================================
    // Public - Getters

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getLockedIssuanceTokens(address user_)
        external
        view
        returns (uint)
    {
        return _lockedIssuanceTokens[user_];
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getOutstandingLoan(address user_) external view returns (uint) {
        return _userTotalOutstandingLoans[user_];
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getLoan(uint loanId_) external view returns (Loan memory loan) {
        return _loans[loanId_];
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getUserLoanIds(address user_)
        external
        view
        returns (uint[] memory loanIds)
    {
        return _userLoans[user_];
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getUserLoans(address user_)
        external
        view
        returns (Loan[] memory loans)
    {
        uint[] memory userLoanIds = _userLoans[user_];
        loans = new Loan[](userLoanIds.length);

        for (uint i = 0; i < userLoanIds.length; i++) {
            loans[i] = _loans[userLoanIds[i]];
        }
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function calculateLoanRepaymentAmount(uint loanId_)
        external
        view
        returns (uint repaymentAmount)
    {
        Loan memory loan = _loans[loanId_];
        if (!loan.isActive) return 0;

        // For now, repayment amount equals remaining principal
        // In the future, this could include interest or other calculations
        return loan.remainingPrincipal;
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getBorrowCapacity() external view returns (uint) {
        return _calculateBorrowCapacity();
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getCurrentBorrowQuota() external view returns (uint) {
        uint borrowCapacity = _calculateBorrowCapacity();
        if (borrowCapacity == 0) return 0;
        return (currentlyBorrowedAmount * 10_000) / borrowCapacity;
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getFloorLiquidityRate() external view returns (uint) {
        uint borrowCapacity = _calculateBorrowCapacity();
        uint borrowableAmount = borrowCapacity * borrowableQuota / 10_000;

        if (borrowableAmount == 0) return 0;

        return ((borrowableAmount - currentlyBorrowedAmount) * 10_000)
            / borrowableAmount;
    }

    /// @inheritdoc ILM_PC_Lending_Facility_v1
    function getUserBorrowingPower(address user_)
        external
        view
        returns (uint)
    {
        return _calculateUserBorrowingPower(user_);
    }

    // =========================================================================
    // Internal

    /// @dev Ensures the borrow amount is valid
    /// @param amount_ The amount to validate
    function _ensureValidBorrowAmount(uint amount_) internal pure {
        if (amount_ == 0) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidBorrowAmount();
        }
    }

    /// @dev Remove a loan from user's loan list
    /// @param user_ The user address
    /// @param loanId_ The loan ID to remove
    function _removeLoanFromUserLoans(address user_, uint loanId_) internal {
        uint[] storage userLoanIds = _userLoans[user_];
        for (uint i = 0; i < userLoanIds.length; i++) {
            if (userLoanIds[i] == loanId_) {
                userLoanIds[i] = userLoanIds[userLoanIds.length - 1];
                userLoanIds.pop();
                break;
            }
        }
    }

    /// @dev Calculate issuance tokens to unlock for a specific loan
    /// @param loan_ The loan details
    /// @param repaymentAmount_ The repayment amount
    /// @return The amount of issuance tokens to unlock
    function _calculateIssuanceTokensToUnlockForLoan(
        Loan memory loan_,
        uint repaymentAmount_
    ) internal pure returns (uint) {
        if (loan_.remainingPrincipal == 0) return 0;

        // Calculate the proportion of the loan being repaid
        uint repaymentProportion =
            (repaymentAmount_ * 1e27) / loan_.remainingPrincipal;

        // Calculate the proportion of locked issuance tokens to unlock
        return (loan_.lockedIssuanceTokens * repaymentProportion) / 1e27;
    }

    /// @dev Calculate the system-wide Borrow Capacity
    /// @return The borrow capacity
    function _calculateBorrowCapacity() internal view returns (uint) {
        // Get the issuance token's total supply (this represents the virtual issuance supply)
        uint virtualIssuanceSupply = IERC20(
            IBondingCurveBase_v1(_dbcFmAddress).getIssuanceToken()
        ).totalSupply();

        uint pFloor = _getFloorPrice();

        // Borrow Capacity = virtualIssuanceSupply * P_floor
        return virtualIssuanceSupply * pFloor / 1e18; // Adjust for decimals
    }

    /// @dev Calculate user's borrowing power based on locked issuance tokens
    /// @param user_ The user address
    /// @return The user's borrowing power
    function _calculateUserBorrowingPower(address user_)
        internal
        view
        returns (uint)
    {
        // Use the DBC FM to get the actual floor price from the first segment
        // User borrowing power = locked issuance tokens * floor price
        uint floorPrice = _getFloorPrice();
        return _lockedIssuanceTokens[user_] * floorPrice / 1e18; // Adjust for decimals
    }

    /// @dev Calculate dynamic borrowing fee using the fee calculator
    /// @param requestedAmount_ The requested loan amount
    /// @return The dynamic borrowing fee
    function _calculateDynamicBorrowingFee(uint requestedAmount_)
        internal
        view
        returns (uint)
    {
        // Calculate fee using the dynamic fee calculator library
        uint utilizationRatio =
            (currentlyBorrowedAmount * 1e18) / _calculateBorrowCapacity();
        uint feeRate = IDynamicFeeCalculator_v1(_dynamicFeeCalculator)
            .calculateOriginationFee(utilizationRatio);
        return (requestedAmount_ * feeRate) / 1e18; // Fee based on calculated rate
    }

    /// @dev Calculate the required collateral amount for a given issuance token amount
    /// @param issuanceTokenAmount_ The amount of issuance tokens
    /// @return The required collateral amount
    function _calculateCollateralAmount(uint issuanceTokenAmount_)
        internal
        view
        returns (uint)
    {
        // Use the DBC FM to get the actual floor price from the first segment
        // Required collateral = issuance tokens * floor price
        uint floorPrice = _getFloorPrice();
        return issuanceTokenAmount_ * floorPrice / 1e18; // Adjust for decimals
    }

    /// @dev Calculate the required issuance tokens for a given borrow amount
    /// @param borrowAmount_ The amount to borrow
    /// @return The required issuance tokens to lock
    function _calculateRequiredIssuanceTokens(uint borrowAmount_)
        internal
        view
        returns (uint)
    {
        // Required issuance tokens = borrow amount / floor price
        uint floorPrice = _getFloorPrice();
        return borrowAmount_ * 1e18 / floorPrice; // Adjust for decimals
    }

    /// @dev Get the current floor price from the DBC FM
    /// @return The current floor price
    function _getFloorPrice() internal view returns (uint) {
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1 dbcFm =
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1(_dbcFmAddress);

        // Get the segments from the funding manager
        PackedSegment[] memory segments = dbcFm.getSegments();

        if (segments.length == 0) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_NoSegmentsConfigured();
        }

        // Return the initial price of the first segment (floor price)
        return PackedSegmentLib._initialPrice(segments[0]);
    }

    /// @dev Internal function that handles all borrowing logic
    function _borrow(
        uint requestedLoanAmount_,
        address tokenReceiver_,
        address borrower_
    ) internal returns (uint loanId_) {
        // Calculate how much issuance tokens need to be locked for this borrow amount
        uint requiredIssuanceTokens =
            _calculateRequiredIssuanceTokens(requestedLoanAmount_);

        // Check if borrowing would exceed borrowable quota
        if (
            currentlyBorrowedAmount + requestedLoanAmount_
                > _calculateBorrowCapacity() * borrowableQuota / 10_000
        ) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_BorrowableQuotaExceeded();
        }

        // Lock the required issuance tokens automatically
        // Transfer Tokens only when the caller is the tokenReceiver_
        if (tokenReceiver_ != address(this)) {
            _issuanceToken.safeTransferFrom(
                _msgSender(), address(this), requiredIssuanceTokens
            );
        }
        _lockedIssuanceTokens[borrower_] += requiredIssuanceTokens;

        // Calculate dynamic borrowing fee
        uint dynamicBorrowingFee =
            _calculateDynamicBorrowingFee(requestedLoanAmount_);
        uint netAmountToUser = requestedLoanAmount_ - dynamicBorrowingFee;

        uint currentFloorPrice = _getFloorPrice();
        uint[] storage userLoanIds = _userLoans[borrower_];

        // Check if borrower has any active loans and if the most recent one has the same floor price
        if (userLoanIds.length > 0) {
            uint lastLoanId = userLoanIds[userLoanIds.length - 1];
            Loan storage lastLoan = _loans[lastLoanId];

            // If the last loan is active and has the same floor price, modify it instead of creating a new one
            if (
                lastLoan.isActive
                    && lastLoan.floorPriceAtBorrow == currentFloorPrice
            ) {
                // Update the existing loan
                lastLoan.principalAmount += requestedLoanAmount_;
                lastLoan.lockedIssuanceTokens += requiredIssuanceTokens;
                lastLoan.remainingPrincipal += requestedLoanAmount_;
                lastLoan.timestamp = block.timestamp;

                // Execute common borrowing logic
                _executeBorrowingLogic(
                    requestedLoanAmount_,
                    dynamicBorrowingFee,
                    netAmountToUser,
                    tokenReceiver_,
                    borrower_,
                    requiredIssuanceTokens,
                    lastLoanId,
                    currentFloorPrice
                );
                return lastLoanId;
            }
        }

        // Create new loan (either no existing loans or floor price changed)
        uint loanId = nextLoanId++;

        _loans[loanId] = Loan({
            id: loanId,
            borrower: borrower_,
            principalAmount: requestedLoanAmount_,
            lockedIssuanceTokens: requiredIssuanceTokens,
            floorPriceAtBorrow: currentFloorPrice,
            remainingPrincipal: requestedLoanAmount_,
            timestamp: block.timestamp,
            isActive: true
        });

        // Add loan to borrower's loan list
        _userLoans[borrower_].push(loanId);

        // Execute common borrowing logic
        _executeBorrowingLogic(
            requestedLoanAmount_,
            dynamicBorrowingFee,
            netAmountToUser,
            tokenReceiver_,
            borrower_,
            requiredIssuanceTokens,
            loanId,
            currentFloorPrice
        );

        return loanId;
    }

    /// @dev Internal function that handles buyAndBorrow logic
    /// @param collateralAmount_ The amount of collateral to use for the operation
    /// @param leverage_ The leverage multiplier for the borrowing
    /// @param borrower_ The address of the user on whose behalf the loan is created
    /// @return loanId_ The ID of the created loan
    function _buyAndBorrow(
        uint collateralAmount_,
        uint leverage_,
        address borrower_
    ) internal returns (uint loanId_) {
        if (leverage_ < 1 || leverage_ > maxLeverage) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_InvalidLeverage();
        }

        if (collateralAmount_ == 0) {
            revert
                ILM_PC_Lending_Facility_v1
                .Module__LM_PC_Lending_Facility_NoCollateralAvailable();
        }

        // Transfer all user's collateral to contract at once
        _collateralToken.safeTransferFrom(
            _msgSender(), address(this), collateralAmount_
        );

        uint remainingCollateral = collateralAmount_;

        // Track the loan ID (will be the same for all iterations due to consolidation)
        uint loanId;

        // Loop through leverage iterations
        for (uint8 i = 0; i < leverage_; i++) {
            // Check if we have any collateral left
            if (remainingCollateral == 0) {
                break;
            }

            // Use all remaining collateral for this iteration
            uint collateralForThisIteration = remainingCollateral;

            // Approve the DBC FM for the collateral for this iteration
            _collateralToken.approve(_dbcFmAddress, collateralForThisIteration);

            // Calculate minimum amount of issuance tokens expected from the purchase
            uint minIssuanceTokensOut = IBondingCurveBase_v1(_dbcFmAddress)
                .calculatePurchaseReturn(collateralForThisIteration);

            // Require minimum issuance tokens to be greater than 0
            if (minIssuanceTokensOut == 0) {
                revert
                    ILM_PC_Lending_Facility_v1
                    .Module__LM_PC_Lending_Facility_InsufficientIssuanceTokensReceived(
                );
            }

            uint issuanceBalanceBefore = _issuanceToken.balanceOf(address(this));

            // Buy issuance tokens from the funding manager - store in contract
            IBondingCurveBase_v1(_dbcFmAddress).buyFor(
                address(this), // receiver (contract instead of user)
                collateralForThisIteration, // deposit amount
                minIssuanceTokensOut // minimum amount out
            );

            // Get the actual amount of issuance tokens received in this iteration
            uint issuanceBalanceAfter = _issuanceToken.balanceOf(address(this));
            uint issuanceTokensReceived =
                issuanceBalanceAfter - issuanceBalanceBefore;
            if (issuanceTokensReceived == 0) {
                revert
                    ILM_PC_Lending_Facility_v1
                    .Module__LM_PC_Lending_Facility_NoIssuanceTokensReceived();
            }

            // Now calculate borrowing power based on balance of issuance
            uint borrowingPower =
                _calculateCollateralAmount(issuanceTokensReceived);

            // If we can't borrow anything more, break the loop
            if (borrowingPower <= 0) {
                break;
            }

            uint collateralBalanceBefore =
                _collateralToken.balanceOf(address(this));

            loanId = _borrow(borrowingPower, address(this), borrower_);

            uint collateralBalanceAfter =
                _collateralToken.balanceOf(address(this));

            remainingCollateral =
                collateralBalanceAfter - collateralBalanceBefore;
        }

        // Return any unused collateral back to the caller
        if (remainingCollateral > 0) {
            _collateralToken.safeTransfer(_msgSender(), remainingCollateral);
        }

        // Emit event for the completed buyAndBorrow operation
        emit BuyAndBorrowCompleted(borrower_, leverage_);

        return loanId;
    }

    /// @dev Execute the common borrowing logic (transfers, state updates, events)
    function _executeBorrowingLogic(
        uint requestedLoanAmount_,
        uint dynamicBorrowingFee_,
        uint netAmountToUser_,
        address tokenReceiver_,
        address user_,
        uint requiredIssuanceTokens_,
        uint loanId_,
        uint currentFloorPrice_
    ) internal {
        // Update state (track gross requested amount as debt; fee is paid at repayment)
        currentlyBorrowedAmount += requestedLoanAmount_;
        _userTotalOutstandingLoans[user_] += requestedLoanAmount_;

        // Pull gross from DBC FM to this module
        IFundingManager_v1(_dbcFmAddress).transferOrchestratorToken(
            address(this), requestedLoanAmount_
        );

        // Transfer fee back to DBC FM (retained to increase base price)
        if (dynamicBorrowingFee_ > 0) {
            _collateralToken.safeTransfer(_dbcFmAddress, dynamicBorrowingFee_);
        }

        // Transfer net amount to collateral receiver
        _collateralToken.safeTransfer(tokenReceiver_, netAmountToUser_);

        // Emit events
        emit IssuanceTokensLocked(user_, requiredIssuanceTokens_);
        emit LoanCreated(
            loanId_, user_, requestedLoanAmount_, currentFloorPrice_
        );
    }
}
