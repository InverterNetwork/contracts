// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

/**
 * @title   House Protocol Lending Facility Interface
 *
 * @notice  Interface for the House Protocol lending facility that allows users to borrow
 *          collateral tokens against issuance tokens with dynamic fee calculation.
 *
 * @dev     This interface defines the following key functionality:
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
interface ILM_PC_HouseProtocol_v1 is IERC20PaymentClientBase_v2 {
    // =========================================================================
    // Events

    /// @notice Emitted when a user borrows collateral tokens
    /// @param user The address of the borrower
    /// @param requestedAmount The requested loan amount
    /// @param fee The dynamic borrowing fee deducted
    /// @param netAmount The net amount received by the user
    event Borrowed(
        address indexed user, uint requestedAmount, uint fee, uint netAmount
    );

    /// @notice Emitted when a user repays their loan
    /// @param user The address of the borrower
    /// @param repaymentAmount The amount repaid
    /// @param issuanceTokensUnlocked The amount of issuance tokens unlocked
    event Repaid(
        address indexed user, uint repaymentAmount, uint issuanceTokensUnlocked
    );

    /// @notice Emitted when a user locks issuance tokens
    /// @param user The address of the user
    /// @param amount The amount of issuance tokens locked
    event IssuanceTokensLocked(address indexed user, uint amount);

    /// @notice Emitted when a user unlocks issuance tokens
    /// @param user The address of the user
    /// @param amount The amount of issuance tokens unlocked
    event IssuanceTokensUnlocked(address indexed user, uint amount);

    /// @notice Emitted when the individual borrow limit is updated
    /// @param newLimit The new individual borrow limit
    event IndividualBorrowLimitUpdated(uint newLimit);

    /// @notice Emitted when the borrowable quota is updated
    /// @param newQuota The new borrowable quota (in basis points)
    event BorrowableQuotaUpdated(uint newQuota);

    /// @notice Emitted when the dynamic fee calculator is updated
    /// @param newCalculator The new fee calculator address
    event DynamicFeeCalculatorUpdated(address newCalculator);

    /// @notice Emitted when the dynamic fee calculator parameters are updated
    /// @param dynamicFeeParameters_ The dynamic fee parameters
    event DynamicFeeCalculatorParamsUpdated(
        DynamicFeeParameters dynamicFeeParameters_
    );

    // =========================================================================
    // Errors

    /// @notice Amount cannot be zero
    error Module__LM_PC_HouseProtocol_InvalidBorrowAmount();

    /// @notice Insufficient borrowing power
    error Module__LM_PC_HouseProtocol_InsufficientBorrowingPower();

    /// @notice Borrowable quota exceeded
    error Module__LM_PC_HouseProtocol_BorrowableQuotaExceeded();

    /// @notice Individual borrow limit exceeded
    error Module__LM_PC_HouseProtocol_IndividualBorrowLimitExceeded();

    /// @notice Repayment amount exceeds outstanding loan
    error Module__LM_PC_HouseProtocol_RepaymentAmountExceedsLoan();

    /// @notice Insufficient locked issuance tokens
    error Module__LM_PC_HouseProtocol_InsufficientLockedTokens();

    /// @notice Cannot unlock tokens with outstanding loan
    error Module__LM_PC_HouseProtocol_CannotUnlockWithOutstandingLoan();

    /// @notice Caller not authorized
    error Module__LM_PC_HouseProtocol_CallerNotAuthorized();

    /// @notice Borrowable quota cannot exceed 100%
    error Module__LM_PC_HouseProtocol_BorrowableQuotaTooHigh();

    /// @notice Invalid fee calculator address (zero address)
    error Module__LM_PC_HouseProtocol_InvalidFeeCalculatorAddress();

    /// @notice Insufficient issuance tokens to lock for borrowing
    error Module__LM_PC_HouseProtocol_InsufficientIssuanceTokens();

    /// @notice Invalid dynamic fee parameters
    error Module__LM_PC_HouseProtocol_InvalidDynamicFeeParameters();

    // =========================================================================
    // Structs

    /// @notice Parameters for the dynamic fee calculator
    /// @dev These parameters are used to calculate the dynamic fee for issuance/redemption and origination fees
    ///      based on the floor liquidity rate.
    ///      Z_issueRedeem: Base fee component for issuance/redemption fees.
    ///      A_issueRedeem: PremiumRate threshold for dynamic issuance/redemption fee adjustment.
    ///      m_issueRedeem: Multiplier for dynamic issuance/redemption fee component.
    ///      Z_origination: Base fee component for origination fees.
    ///      A_origination: FloorLiquidityRate threshold for dynamic origination fee adjustment.
    ///      m_origination: Multiplier for dynamic origination fee component.
    struct DynamicFeeParameters {
        uint Z_issueRedeem;
        uint A_issueRedeem;
        uint m_issueRedeem;
        uint Z_origination;
        uint A_origination;
        uint m_origination;
    }

    // =========================================================================
    // Public - Getters

    /// @notice Returns the amount of issuance tokens locked by a user
    /// @param user_ The address of the user
    /// @return amount_ The amount of locked issuance tokens
    function getLockedIssuanceTokens(address user_)
        external
        view
        returns (uint amount_);

    /// @notice Returns the outstanding loan amount for a user
    /// @param user_ The address of the user
    /// @return amount_ The outstanding loan amount
    function getOutstandingLoan(address user_)
        external
        view
        returns (uint amount_);

    /// @notice Returns the system-wide Borrow Capacity
    /// @return capacity_ The borrow capacity
    function getBorrowCapacity() external view returns (uint capacity_);

    /// @notice Returns the current borrow quota as a percentage of borrow capacity
    /// @return quota_ The current borrow quota (in basis points)
    function getCurrentBorrowQuota() external view returns (uint quota_);

    /// @notice Returns the floor liquidity rate
    /// @return rate_ The floor liquidity rate (in basis points)
    function getFloorLiquidityRate() external view returns (uint rate_);

    /// @notice Returns the borrowing power for a specific user
    /// @param user_ The address of the user
    /// @return power_ The user's borrowing power
    function getUserBorrowingPower(address user_)
        external
        view
        returns (uint power_);

    /// @notice Returns the dynamic fee parameters
    /// @return dynamicFeeParameters_ The dynamic fee parameters
    function getDynamicFeeParameters()
        external
        view
        returns (DynamicFeeParameters memory dynamicFeeParameters_);

    // =========================================================================
    // Public - Mutating

    /// @notice Borrow collateral tokens against locked issuance tokens
    /// @param requestedLoanAmount_ The amount of collateral tokens to borrow
    function borrow(uint requestedLoanAmount_) external;

    /// @notice Repay a loan with collateral tokens
    /// @param repaymentAmount_ The amount of collateral tokens to repay
    function repay(uint repaymentAmount_) external;

    /// @notice Unlock issuance tokens (only if no outstanding loan)
    /// @param amount_ The amount of issuance tokens to unlock
    function unlockIssuanceTokens(uint amount_) external;

    // =========================================================================
    // Public - Configuration (Lending Facility Manager only)

    /// @notice Set the individual borrow limit
    /// @param newIndividualBorrowLimit_ The new individual borrow limit
    function setIndividualBorrowLimit(uint newIndividualBorrowLimit_)
        external;

    /// @notice Set the borrowable quota
    /// @param newBorrowableQuota_ The new borrowable quota (in basis points)
    function setBorrowableQuota(uint newBorrowableQuota_) external;

    /// @notice Set the Dynamic Fee Calculator address
    /// @param newFeeCalculator_ The new fee calculator address
    function setDynamicFeeCalculator(address newFeeCalculator_) external;

    /// @notice Set the Dynamic Fee Calculator parameters
    /// @param dynamicFeeParameters_ The dynamic fee parameters
    function setDynamicFeeCalculatorParams(
        DynamicFeeParameters memory dynamicFeeParameters_
    ) external;
}
