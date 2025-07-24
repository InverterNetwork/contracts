// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

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

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// System under Test (SuT)
import {ILM_PC_HouseProtocol_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_HouseProtocol_v1.sol";
import {
    IFM_BC_Discrete_Redeeming_VirtualSupply_v1
} from "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {
    IVirtualCollateralSupplyBase_v1
} from "src/modules/fundingManager/bondingCurve/interfaces/IVirtualCollateralSupplyBase_v1.sol";
import {DynamicFeeCalculatorLib_v1} from
    "src/modules/logicModule/libraries/DynamicFeeCalculator_v1.sol";

/**
 * @title   House Protocol Lending Facility Logic Module
 *
 * @notice  A lending facility that allows users to borrow collateral tokens against issuance tokens.
 *          The system uses dynamic fee calculation based on liquidity rates and enforces borrowing limits.
 *
 * @dev     This contract implements the following key functionality:
 *          - Borrowing collateral tokens against locked issuance tokens
 *          - Dynamic fee calculation based on floor liquidity rate
 *          - Repayment functionality with issuance token unlocking
 *          - Configurable borrowing limits and quotas
 *          - Role-based access control for facility management
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
contract LM_PC_HouseProtocol_v1 is
    ILM_PC_HouseProtocol_v1,
    ERC20PaymentClientBase_v2
{
    // =========================================================================
    // Libraries

    using SafeERC20 for IERC20;
    using DynamicFeeCalculatorLib_v1 for uint;

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
        return interfaceId_ == type(ILM_PC_HouseProtocol_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @notice Maximum borrowable quota percentage (100%)
    uint internal constant _MAX_BORROWABLE_QUOTA = 10_000; // 100% in basis points

    //--------------------------------------------------------------------------
    // State

    /// @dev The role that allows managing the lending facility
    bytes32 public constant LENDING_FACILITY_MANAGER_ROLE =
        "LENDING_FACILITY_MANAGER";

    /// @dev The role for managing the dynamic fee calculator
    bytes32 public constant FEE_CALCULATOR_ADMIN_ROLE = "FEE_CALCULATOR_ADMIN";

    /// @notice Address of the Dynamic Fee Calculator contract
    address public dynamicFeeCalculator;

    /// @notice Borrowable Quota as percentage of Borrow Capacity (in basis points)
    uint public borrowableQuota;

    /// @notice Individual borrow limit per user
    uint public individualBorrowLimit;

    /// @notice Currently borrowed amount across all users
    uint public currentlyBorrowedAmount;

    /// @notice Mapping of user addresses to their locked issuance token amounts
    mapping(address user => uint amount) internal _lockedIssuanceTokens;

    /// @notice Mapping of user addresses to their outstanding loan principals
    mapping(address user => uint amount) internal _outstandingLoans;

    /// @notice Collateral token (the token being borrowed)
    IERC20 internal _collateralToken;

    /// @notice Issuance token (the token being locked as collateral)
    IERC20 internal _issuanceToken;

    /// @notice DBC FM address for floor price calculations
    address internal _dbcFmAddress;

    /// @notice Base fee component for issuance/redemption fees (as per formulas in 6.4.2).
    uint public Z_issueRedeem;

    /// @notice premiumRate threshold for dynamic issuance/redemption fee adjustment (as per formulas in 6.4.2).
    uint public A_issueRedeem;

    /// @notice Multiplier for dynamic issuance/redemption fee component (as per formulas in 6.4.2).
    uint public m_issueRedeem;

    /// @notice Base fee component for origination fees (as per formula in 6.4.1).
    uint public Z_origination;

    /// @notice floorLiquidityRate threshold for dynamic origination fee adjustment (as per formula in 6.4.1).
    uint public A_origination;

    /// @notice Multiplier for dynamic origination fee component (as per formula in 6.4.1).
    uint public m_origination;

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

    modifier onlyFeeCalculatorAdmin() {
        _checkRoleModifier(FEE_CALCULATOR_ADMIN_ROLE, _msgSender());
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
            uint borrowableQuota_,
            uint individualBorrowLimit_
        ) = abi.decode(configData_, (address, address, address, uint, uint));

        // Set init state
        _collateralToken = IERC20(collateralToken);
        _issuanceToken = IERC20(issuanceToken);
        _dbcFmAddress = dbcFmAddress;
        borrowableQuota = borrowableQuota_;
        individualBorrowLimit = individualBorrowLimit_;
    }

    // =========================================================================
    // Public - Mutating

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function borrow(uint requestedLoanAmount_)
        external
        virtual
        onlyValidBorrowAmount(requestedLoanAmount_)
    {
        address user = _msgSender();

        // Calculate user's borrowing power based on their available issuance tokens
        uint userIssuanceTokens = _issuanceToken.balanceOf(user);
        uint userBorrowingPower = userIssuanceTokens * _getFloorPrice() / 1e18;

        // Ensure user has sufficient borrowing power
        if (requestedLoanAmount_ > userBorrowingPower) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InsufficientBorrowingPower();
        }

        // Calculate how much issuance tokens need to be locked for this borrow amount
        uint requiredIssuanceTokens = _calculateRequiredIssuanceTokens(requestedLoanAmount_);
        
        // Ensure user has sufficient issuance tokens to lock
        if (userIssuanceTokens < requiredIssuanceTokens) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InsufficientIssuanceTokens();
        }

        // Check if borrowing would exceed borrowable quota
        if (currentlyBorrowedAmount + requestedLoanAmount_
                > _calculateBorrowCapacity() * borrowableQuota / 10_000) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_BorrowableQuotaExceeded();
        }

        // Check individual borrow limit
        if (requestedLoanAmount_ > individualBorrowLimit) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_IndividualBorrowLimitExceeded();
        }

        // Lock the required issuance tokens automatically
        _issuanceToken.safeTransferFrom(user, address(this), requiredIssuanceTokens);
        _lockedIssuanceTokens[user] += requiredIssuanceTokens;

        // Calculate dynamic borrowing fee
        uint dynamicBorrowingFee =
            _calculateDynamicBorrowingFee(requestedLoanAmount_);
        uint netAmountToUser = requestedLoanAmount_ - dynamicBorrowingFee;

        // Update state
        currentlyBorrowedAmount += requestedLoanAmount_;
        _outstandingLoans[user] += requestedLoanAmount_;

        // Transfer fee to fee manager
        if (dynamicBorrowingFee > 0) {
            _collateralToken.safeTransfer(
                __Module_orchestrator.governor().getFeeManager(),
                dynamicBorrowingFee
            );
        }

        // Transfer net amount to user
        _collateralToken.safeTransfer(user, netAmountToUser);

        // Emit events
        emit IssuanceTokensLocked(user, requiredIssuanceTokens);
        emit Borrowed(
            user, requestedLoanAmount_, dynamicBorrowingFee, netAmountToUser
        );
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function repay(uint repaymentAmount_) external virtual {
        address user = _msgSender();

        if (_outstandingLoans[user] < repaymentAmount_) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_RepaymentAmountExceedsLoan();
        }

        // Update state
        _outstandingLoans[user] -= repaymentAmount_;
        currentlyBorrowedAmount -= repaymentAmount_;

        // Transfer collateral back to lending facility
        _collateralToken.safeTransferFrom(user, address(this), repaymentAmount_);

        // Calculate and unlock issuance tokens
        uint issuanceTokensToUnlock =
            _calculateIssuanceTokensToUnlock(user, repaymentAmount_);

        if (issuanceTokensToUnlock > 0) {
            _lockedIssuanceTokens[user] -= issuanceTokensToUnlock;
            _issuanceToken.safeTransfer(user, issuanceTokensToUnlock);
        }

        // Emit event
        emit Repaid(user, repaymentAmount_, issuanceTokensToUnlock);
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function unlockIssuanceTokens(uint amount_) external virtual {
        address user = _msgSender();

        if (_lockedIssuanceTokens[user] < amount_) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InsufficientLockedTokens();
        }

        if (_outstandingLoans[user] > 0) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_CannotUnlockWithOutstandingLoan();
        }

        // Update locked amount
        _lockedIssuanceTokens[user] -= amount_;

        // Transfer tokens back to user
        _issuanceToken.safeTransfer(user, amount_);

        // Emit event
        emit IssuanceTokensUnlocked(user, amount_);
    }

    // =========================================================================
    // Public - Configuration (Lending Facility Manager only)

    /// @notice Set the individual borrow limit
    /// @param newIndividualBorrowLimit_ The new individual borrow limit
    function setIndividualBorrowLimit(uint newIndividualBorrowLimit_)
        external
        onlyLendingFacilityManager
    {
        individualBorrowLimit = newIndividualBorrowLimit_;
        emit IndividualBorrowLimitUpdated(newIndividualBorrowLimit_);
    }

    /// @notice Set the borrowable quota
    /// @param newBorrowableQuota_ The new borrowable quota (in basis points)
    function setBorrowableQuota(uint newBorrowableQuota_)
        external
        onlyLendingFacilityManager
    {
        if (newBorrowableQuota_ > _MAX_BORROWABLE_QUOTA) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_BorrowableQuotaTooHigh();
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
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InvalidFeeCalculatorAddress();
        }
        dynamicFeeCalculator = newFeeCalculator_;
        emit DynamicFeeCalculatorUpdated(newFeeCalculator_);
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function setDynamicFeeCalculatorParams(
        uint Z_issueRedeem_,
        uint A_issueRedeem_,
        uint m_issueRedeem_,
        uint Z_origination_,
        uint A_origination_,
        uint m_origination_
    ) external onlyFeeCalculatorAdmin {
        Z_issueRedeem = Z_issueRedeem_;
        A_issueRedeem = A_issueRedeem_;
        m_issueRedeem = m_issueRedeem_;
        Z_origination = Z_origination_;
        A_origination = A_origination_;
        m_origination = m_origination_;
        emit DynamicFeeCalculatorParamsUpdated(
            Z_issueRedeem_,
            A_issueRedeem_,
            m_issueRedeem_,
            Z_origination_,
            A_origination_,
            m_origination_
        );
    }

    // =========================================================================
    // Public - Getters

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function getLockedIssuanceTokens(address user_)
        external
        view
        returns (uint)
    {
        return _lockedIssuanceTokens[user_];
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function getOutstandingLoan(address user_) external view returns (uint) {
        return _outstandingLoans[user_];
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function getBorrowCapacity() external view returns (uint) {
        return _calculateBorrowCapacity();
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function getCurrentBorrowQuota() external view returns (uint) {
        uint borrowCapacity = _calculateBorrowCapacity();
        if (borrowCapacity == 0) return 0;
        return (currentlyBorrowedAmount * 10_000) / borrowCapacity;
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function getFloorLiquidityRate() external view returns (uint) {
        uint borrowCapacity = _calculateBorrowCapacity();
        uint borrowableAmount = borrowCapacity * borrowableQuota / 10_000;

        if (borrowableAmount == 0) return 0;

        return ((borrowableAmount - currentlyBorrowedAmount) * 10_000)
            / borrowableAmount;
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function getUserBorrowingPower(address user_)
        external
        view
        returns (uint)
    {
        return _calculateUserBorrowingPower(user_);
    }

    //--------------------------------------------------------------------------
    // Internal

    /// @dev Ensures the borrow amount is valid
    /// @param amount_ The amount to validate
    function _ensureValidBorrowAmount(uint amount_) internal pure {
        if (amount_ == 0) {
            revert ILM_PC_HouseProtocol_v1.Module__LM_PC_HouseProtocol_InvalidBorrowAmount();
        }
    }

    /// @dev Calculate the system-wide Borrow Capacity
    /// @return The borrow capacity
    function _calculateBorrowCapacity() internal view returns (uint) {
        // Use the DBC FM to get the actual virtual collateral supply
        // Borrow capacity = virtual collateral supply (this represents the total backing)
        IVirtualCollateralSupplyBase_v1 dbcFm = 
            IVirtualCollateralSupplyBase_v1(_dbcFmAddress);
        return dbcFm.getVirtualCollateralSupply();
    }

    /// @dev Calculate user's borrowing power based on locked issuance tokens
    /// @param user_ The user address
    /// @return The user's borrowing power
    function _calculateUserBorrowingPower(address user_)
        internal
        view
        returns (uint)
    {
        // Use the DBC FM to get the actual floor price
        // User borrowing power = locked issuance tokens * floor price
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1 dbcFm = 
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1(_dbcFmAddress);
        uint floorPrice = dbcFm.getStaticPriceForBuying();
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
        if (dynamicFeeCalculator == address(0)) {
            return 0; // No fee if no calculator is set
        }

        // Calculate fee based on floor liquidity rate
        uint floorLiquidityRate = this.getFloorLiquidityRate();
        return (requestedAmount_ * floorLiquidityRate) / 10_000; // Fee based on liquidity rate
    }

    /// @dev Calculate issuance tokens to unlock based on repayment amount
    /// @param user_ The user address
    /// @param repaymentAmount_ The repayment amount
    /// @return The amount of issuance tokens to unlock
    function _calculateIssuanceTokensToUnlock(
        address user_,
        uint repaymentAmount_
    ) internal view returns (uint) {
        if (_outstandingLoans[user_] == 0) return 0;

        // Calculate the proportion of the loan being repaid
        uint repaymentProportion =
            (repaymentAmount_ * 10_000) / _outstandingLoans[user_];

        // Calculate the proportion of locked issuance tokens to unlock
        return (_lockedIssuanceTokens[user_] * repaymentProportion) / 10_000;
    }

    /// @dev Calculate the required collateral amount for a given issuance token amount
    /// @param issuanceTokenAmount_ The amount of issuance tokens
    /// @return The required collateral amount
    function _calculateCollateralAmount(uint issuanceTokenAmount_)
        internal
        view
        returns (uint)
    {
        // Use the DBC FM to get the actual floor price
        // Required collateral = issuance tokens * floor price
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1 dbcFm = 
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1(_dbcFmAddress);
        uint floorPrice = dbcFm.getStaticPriceForBuying();
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
    function _getFloorPrice()
        internal
        view
        returns (uint)
    {
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1 dbcFm = 
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1(_dbcFmAddress);
        return dbcFm.getStaticPriceForBuying();
    }
}
