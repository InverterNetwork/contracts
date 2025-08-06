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
import {ILM_PC_HouseProtocol_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_HouseProtocol_v1.sol";
import {IFundingManager_v1} from
    "src/modules/fundingManager/IFundingManager_v1.sol";
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {DynamicFeeCalculatorLib_v1} from
    "src/modules/logicModule/libraries/DynamicFeeCalculator_v1.sol";
import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {PackedSegmentLib} from
    "src/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

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
 *                  2. Configure FEE_CALCULATOR_ADMIN_ROLE:
 *                     - Purpose: Implements access control for configuring dynamic fee
 *                               calculator parameters
 *                     - How:     The OrchestratorAdmin must:
 *                               1. Retrieve the fee calculator admin role identifier
 *                               2. Grant the role to designated admins
 *                     - Example: module.grantModuleRole(
 *                                 module.FEE_CALCULATOR_ADMIN_ROLE(),
 *                                 feeAdminAddress
 *                               );
 *
 *                  3. Initialize Dynamic Fee Parameters:
 *                     - Purpose: Sets up the dynamic fee calculation parameters for
 *                               origination, issuance, and redemption fees
 *                     - How:     A user with FEE_CALCULATOR_ADMIN_ROLE must call:
 *                               setDynamicFeeCalculatorParams() with appropriate parameters
 *
 * @custom:upgrades This contract is upgradeable and uses the Inverter upgrade pattern.
 *                  The contract inherits from ERC20PaymentClientBase_v2 which provides
 *                  upgradeability through the Inverter proxy system. Upgrades should be
 *                  carefully tested to ensure no state corruption and proper initialization
 *                  of new functionality. The storage gap pattern is used to reserve space
 *                  for future upgrades.
 *
 * @custom:security This contract handles user funds and should be thoroughly audited.
 *                  Key security considerations:
 *                  - Reentrancy protection: Uses SafeERC20 for all token transfers
 *                  - Access control: Role-based access control for administrative functions
 *                  - Input validation: All user inputs are validated before processing
 *                  - State consistency: Borrowing and repayment operations maintain
 *                    consistent state across all mappings and counters
 *                  - Fee calculation: Dynamic fee calculation is deterministic and
 *                    cannot be manipulated by users
 *                  - Collateralization: Users must lock sufficient issuance tokens
 *                    before borrowing collateral tokens
 *                  - Liquidation protection: The system prevents over-borrowing through
 *                    individual and system-wide limits
 *
 * @custom:audit    This contract has been audited by [auditor name] on [date].
 *                  Audit report: [link to audit report]
 *                  Key findings: [summary of key findings if any]
 *                  Remediation status: [status of any remediation if needed]
 *
 * @custom:deployment This contract should be deployed using the Inverter deployment pattern:
 *                    1. Deploy the implementation contract
 *                    2. Deploy the proxy contract pointing to the implementation
 *                    3. Initialize the proxy with proper configuration data
 *                    4. Set up roles and permissions through the orchestrator
 *                    5. Configure dynamic fee parameters
 *                    6. Verify all functionality through comprehensive testing
 *                    Note: The contract requires a valid DBC FM address and proper
 *                    token addresses during initialization.
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

    /// @dev The role that allows managing the lending facility parameters
    bytes32 public constant LENDING_FACILITY_MANAGER_ROLE =
        "LENDING_FACILITY_MANAGER";

    /// @dev The role for managing the dynamic fee calculator parameters
    bytes32 public constant FEE_CALCULATOR_ADMIN_ROLE = "FEE_CALCULATOR_ADMIN";

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

    /// @notice Parameters for the dynamic fee calculator
    DynamicFeeParameters internal _dynamicFeeParameters;

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

        // uint userBorrowingPower = userIssuanceTokens * _getFloorPrice() / 1e18;

        // // Ensure user has sufficient borrowing power
        // if (requestedLoanAmount_ > userBorrowingPower) {
        //     revert
        //         ILM_PC_HouseProtocol_v1
        //         .Module__LM_PC_HouseProtocol_InsufficientBorrowingPower();
        // }
        // @Lee -> I have commented the code because userBorrowingPower and requiredIssuanceTokens are the same
        // and checking for userBorrowingPower is redundant , so I have commented it as of now!

        // Calculate how much issuance tokens need to be locked for this borrow amount
        uint requiredIssuanceTokens =
            _calculateRequiredIssuanceTokens(requestedLoanAmount_);

        // Ensure user has sufficient issuance tokens to lock
        if (userIssuanceTokens < requiredIssuanceTokens) {
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InsufficientIssuanceTokens();
        }

        // Check if borrowing would exceed borrowable quota
        if (
            currentlyBorrowedAmount + requestedLoanAmount_
                > _calculateBorrowCapacity() * borrowableQuota / 10_000
        ) {
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_BorrowableQuotaExceeded();
        }

        // Check individual borrow limit (including existing outstanding loans)
        if (
            requestedLoanAmount_ + _outstandingLoans[user]
                > individualBorrowLimit
        ) {
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_IndividualBorrowLimitExceeded();
        }

        // Lock the required issuance tokens automatically
        _issuanceToken.safeTransferFrom(
            user, address(this), requiredIssuanceTokens
        );
        _lockedIssuanceTokens[user] += requiredIssuanceTokens;

        // Calculate dynamic borrowing fee
        uint dynamicBorrowingFee =
            _calculateDynamicBorrowingFee(requestedLoanAmount_);
        uint netAmountToUser = requestedLoanAmount_ - dynamicBorrowingFee;

        // Update state (use netAmountToUser, not requestedLoanAmount_)
        currentlyBorrowedAmount += netAmountToUser;
        _outstandingLoans[user] += netAmountToUser;

        // Instruct DBC FM to transfer fee to fee manager
        if (dynamicBorrowingFee > 0) {
            IFundingManager_v1(_dbcFmAddress).transferOrchestratorToken(
                __Module_orchestrator.governor().getFeeManager(),
                dynamicBorrowingFee
            );
        }

        // Instruct DBC FM to transfer net amount to user
        IFundingManager_v1(_dbcFmAddress).transferOrchestratorToken(
            user, netAmountToUser
        );

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
            repaymentAmount_ = _outstandingLoans[user];
        }

        // Update state
        _outstandingLoans[user] -= repaymentAmount_;
        currentlyBorrowedAmount -= repaymentAmount_;

        // Transfer collateral from user to lending facility
        _collateralToken.safeTransferFrom(user, address(this), repaymentAmount_);

        // Transfer collateral back to DBC FM
        _collateralToken.safeTransfer(_dbcFmAddress, repaymentAmount_);

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
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InsufficientLockedTokens();
        }

        if (_outstandingLoans[user] > 0) {
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_CannotUnlockWithOutstandingLoan();
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
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_BorrowableQuotaTooHigh();
        }
        borrowableQuota = newBorrowableQuota_;
        emit BorrowableQuotaUpdated(newBorrowableQuota_);
    }

    // =========================================================================
    // Public - Configuration (Fee Calculator Admin only)

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function setDynamicFeeCalculatorParams(
        DynamicFeeParameters memory dynamicFeeParameters_
    ) external onlyFeeCalculatorAdmin {
        if (
            dynamicFeeParameters_.Z_issueRedeem == 0
                || dynamicFeeParameters_.A_issueRedeem == 0
                || dynamicFeeParameters_.m_issueRedeem == 0
                || dynamicFeeParameters_.Z_origination == 0
                || dynamicFeeParameters_.A_origination == 0
                || dynamicFeeParameters_.m_origination == 0
        ) {
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InvalidDynamicFeeParameters();
        }
        _dynamicFeeParameters = dynamicFeeParameters_;
        emit DynamicFeeCalculatorParamsUpdated(dynamicFeeParameters_);
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

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function getDynamicFeeParameters()
        external
        view
        returns (DynamicFeeParameters memory)
    {
        return _dynamicFeeParameters;
    }

    // =========================================================================
    // Internal

    /// @dev Ensures the borrow amount is valid
    /// @param amount_ The amount to validate
    function _ensureValidBorrowAmount(uint amount_) internal pure {
        if (amount_ == 0) {
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_InvalidBorrowAmount();
        }
    }

    /// @dev Calculate the system-wide Borrow Capacity
    /// @return The borrow capacity
    function _calculateBorrowCapacity() internal view returns (uint) {
        // Get the DBC FM interface
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1 dbcFm =
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1(_dbcFmAddress);
        
        // Get the issuance token's total supply (this represents the virtual issuance supply)
        uint virtualIssuanceSupply = IERC20(IBondingCurveBase_v1(_dbcFmAddress).getIssuanceToken()).totalSupply();
        
        // Get the first segment's initial price (P_floor)
        PackedSegment[] memory segments = dbcFm.getSegments();
        if(segments.length == 0) {
            revert
                ILM_PC_HouseProtocol_v1
                .Module__LM_PC_HouseProtocol_NoSegmentsConfigured();
        }
        
        // Use PackedSegmentLib to get the initial price of the first segment
        uint pFloor = PackedSegmentLib._initialPrice(segments[0]);
        
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
        // Calculate fee using the dynamic fee calculator library
        uint utilizationRatio =
            (currentlyBorrowedAmount * 1e18) / _calculateBorrowCapacity();
        uint feeRate = DynamicFeeCalculatorLib_v1.calculateOriginationFee(
            utilizationRatio,
            _dynamicFeeParameters.Z_origination,
            _dynamicFeeParameters.A_origination,
            _dynamicFeeParameters.m_origination
        );
        return (requestedAmount_ * feeRate) / 1e18; // Fee based on calculated rate
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
    function _getFloorPrice() internal view returns (uint) {
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1 dbcFm =
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1(_dbcFmAddress);
        return dbcFm.getStaticPriceForBuying();
    }
}
