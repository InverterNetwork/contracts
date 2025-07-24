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

        // Calculate user's borrowing power based on locked issuance tokens
        uint userBorrowingPower = _calculateUserBorrowingPower(user);

        // Ensure user has sufficient borrowing power
        require(
            requestedLoanAmount_ <= userBorrowingPower,
            "Insufficient borrowing power"
        );

        // Check if borrowing would exceed borrowable quota
        require(
            currentlyBorrowedAmount + requestedLoanAmount_
                <= _calculateBorrowCapacity() * borrowableQuota / 10_000,
            "Borrowable quota exceeded"
        );

        // Check individual borrow limit
        require(
            requestedLoanAmount_ <= individualBorrowLimit,
            "Individual borrow limit exceeded"
        );

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

        // Emit event
        emit Borrowed(
            user, requestedLoanAmount_, dynamicBorrowingFee, netAmountToUser
        );
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function repay(uint repaymentAmount_) external virtual {
        address user = _msgSender();

        require(
            _outstandingLoans[user] >= repaymentAmount_,
            "Repayment amount exceeds outstanding loan"
        );

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
    function lockIssuanceTokens(uint amount_) external virtual {
        address user = _msgSender();

        require(amount_ > 0, "Amount must be greater than zero");

        // Transfer issuance tokens from user to contract
        _issuanceToken.safeTransferFrom(user, address(this), amount_);

        // Update locked amount
        _lockedIssuanceTokens[user] += amount_;

        // Emit event
        emit IssuanceTokensLocked(user, amount_);
    }

    /// @inheritdoc ILM_PC_HouseProtocol_v1
    function unlockIssuanceTokens(uint amount_) external virtual {
        address user = _msgSender();

        require(
            _lockedIssuanceTokens[user] >= amount_,
            "Insufficient locked issuance tokens"
        );

        require(
            _outstandingLoans[user] == 0,
            "Cannot unlock tokens with outstanding loan"
        );

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
        require(
            newBorrowableQuota_ <= _MAX_BORROWABLE_QUOTA,
            "Borrowable quota cannot exceed 100%"
        );
        borrowableQuota = newBorrowableQuota_;
        emit BorrowableQuotaUpdated(newBorrowableQuota_);
    }

    /// @notice Set the Dynamic Fee Calculator address
    /// @param newFeeCalculator_ The new fee calculator address
    function setDynamicFeeCalculator(address newFeeCalculator_)
        external
        onlyLendingFacilityManager
    {
        require(
            newFeeCalculator_ != address(0), "Invalid fee calculator address"
        );
        dynamicFeeCalculator = newFeeCalculator_;
        emit DynamicFeeCalculatorUpdated(newFeeCalculator_);
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
        require(amount_ > 0, "Borrow amount must be greater than zero");
    }

    /// @dev Calculate the system-wide Borrow Capacity
    /// @return The borrow capacity
    function _calculateBorrowCapacity() internal view returns (uint) {
        // This would need to be implemented based on the actual DBC FM interface
        // For now, returning a placeholder value
        // In reality, this would be: virtualIssuanceSupply * P_floor
        return 1_000_000 ether; // Placeholder
    }

    /// @dev Calculate user's borrowing power based on locked issuance tokens
    /// @param user_ The user address
    /// @return The user's borrowing power
    function _calculateUserBorrowingPower(address user_)
        internal
        view
        returns (uint)
    {
        // This would need to be implemented based on the actual DBC FM interface
        // For now, returning a placeholder calculation
        // In reality, this would be: UserLockedIssuanceTokens * P_floor
        return _lockedIssuanceTokens[user_] * 2; // Placeholder: 2x leverage
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

        // This would need to be implemented based on the actual fee calculator interface
        // For now, returning a placeholder calculation
        uint floorLiquidityRate = this.getFloorLiquidityRate();
        return (requestedAmount_ * floorLiquidityRate) / 10_000; // Placeholder: 1% fee
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
}
