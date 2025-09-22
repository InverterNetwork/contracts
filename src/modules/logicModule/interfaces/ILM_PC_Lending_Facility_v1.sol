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
 *          Each loan is tracked individually with a unique ID to handle floor price changes properly.
 *
 * @dev     This interface defines the following key functionality:
 *          - Borrowing collateral tokens against locked issuance tokens
 *          - Dynamic fee calculation based on floor liquidity rate
 *          - Repayment functionality with issuance token unlocking
 *          - Configurable borrowing limits and quotas
 *          - Role-based access control for facility management
 *          - Individual loan tracking with unique IDs for proper floor price handling
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
interface ILM_PC_Lending_Facility_v1 is IERC20PaymentClientBase_v2 {
    // =========================================================================
    // Structs

    /// @notice Represents an individual loan with its specific terms
    /// @dev Each loan is tracked separately to handle floor price changes properly
    struct Loan {
        uint id; // Unique loan identifier
        address borrower; // Address of the borrower
        uint principalAmount; // Original loan amount (collateral tokens)
        uint lockedIssuanceTokens; // Issuance tokens locked for this specific loan
        uint floorPriceAtBorrow; // Floor price when the loan was taken
        uint remainingPrincipal; // Remaining principal to be repaid
        uint timestamp; // Block timestamp when loan was created
        bool isActive; // Whether the loan is still active
    }

    // =========================================================================
    // Events

    /// @notice Emitted when a new loan is created
    /// @param loanId The unique loan identifier
    /// @param borrower The address of the borrower
    /// @param principalAmount The principal amount of the loan
    /// @param floorPriceAtBorrow The floor price when the loan was taken
    event LoanCreated(
        uint indexed loanId,
        address indexed borrower,
        uint principalAmount,
        uint floorPriceAtBorrow
    );

    /// @notice Emitted when a specific loan is repaid
    /// @param loanId The unique loan identifier
    /// @param borrower The address of the borrower
    /// @param repaymentAmount The amount repaid for this loan
    /// @param issuanceTokensUnlocked The amount of issuance tokens unlocked for this loan
    event LoanRepaid(
        uint indexed loanId,
        address indexed borrower,
        uint repaymentAmount,
        uint issuanceTokensUnlocked
    );

    /// @notice Emitted when a user locks issuance tokens
    /// @param user The address of the user
    /// @param amount The amount of issuance tokens locked
    event IssuanceTokensLocked(address indexed user, uint amount);

    /// @notice Emitted when a user unlocks issuance tokens
    /// @param user The address of the user
    /// @param amount The amount of issuance tokens unlocked
    event IssuanceTokensUnlocked(address indexed user, uint amount);

    /// @notice Emitted when the borrowable quota is updated
    /// @param newQuota The new borrowable quota (in basis points)
    event BorrowableQuotaUpdated(uint newQuota);

    /// @notice Emitted when the dynamic fee calculator is updated
    /// @param newCalculator The new fee calculator address
    event DynamicFeeCalculatorUpdated(address newCalculator);

    /// @notice Emitted when a user completes a buyAndBorrow operation
    /// @param user The address of the user who performed the operation
    /// @param leverage The leverage used for the operation
    /// @param totalIssuanceTokensReceived Total issuance tokens received from all iterations
    /// @param totalBorrowed Total amount borrowed across all iterations
    /// @param collateralUsed Total collateral used for the operation
    event BuyAndBorrowCompleted(
        address indexed user,
        uint leverage,
        uint totalIssuanceTokensReceived,
        uint totalBorrowed,
        uint collateralUsed
    );

    /// @notice Emitted when the maximum leverage is updated
    /// @param newMaxLeverage The new maximum leverage
    event MaxLeverageUpdated(uint newMaxLeverage);

    // =========================================================================
    // Errors

    /// @notice Amount cannot be zero
    error Module__LM_PC_Lending_Facility_InvalidBorrowAmount();

    /// @notice Borrowing would exceed the system-wide borrowable quota
    error Module__LM_PC_Lending_Facility_BorrowableQuotaExceeded();

    /// @notice Borrowable quota cannot exceed 100% (10,000 basis points)
    error Module__LM_PC_Lending_Facility_BorrowableQuotaTooHigh();

    /// @notice No segments are configured in the DBC FM
    error Module__LM_PC_Lending_Facility_NoSegmentsConfigured();

    /// @notice Invalid fee calculator address
    error Module__LM_PC_Lending_Facility_InvalidFeeCalculatorAddress();

    /// @notice Leverage must be at least 1
    error Module__LM_PC_Lending_Facility_InvalidLeverage();

    /// @notice No collateral tokens available for the user
    error Module__LM_PC_Lending_Facility_NoCollateralAvailable();

    /// @notice Insufficient issuance tokens would be received from purchase
    error Module__LM_PC_Lending_Facility_InsufficientIssuanceTokensReceived();

    /// @notice No issuance tokens received in iteration
    error Module__LM_PC_Lending_Facility_NoIssuanceTokensReceived();

    /// @notice Invalid loan ID or loan does not belong to caller
    error Module__LM_PC_Lending_Facility_InvalidLoanId();

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

    /// @notice Get details of a specific loan
    /// @param loanId_ The loan ID
    /// @return loan The loan details
    function getLoan(uint loanId_) external view returns (Loan memory loan);

    /// @notice Get all active loan IDs for a user
    /// @param user_ The user address
    /// @return loanIds Array of active loan IDs
    function getUserLoanIds(address user_)
        external
        view
        returns (uint[] memory loanIds);

    /// @notice Get all active loans for a user
    /// @param user_ The user address
    /// @return loans Array of active loan details
    function getUserLoans(address user_)
        external
        view
        returns (Loan[] memory loans);

    /// @notice Calculate the repayment amount for a specific loan based on current floor price
    /// @param loanId_ The loan ID
    /// @return repaymentAmount The amount needed to fully repay the loan
    function calculateLoanRepaymentAmount(uint loanId_)
        external
        view
        returns (uint repaymentAmount);

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

    // =========================================================================
    // Public - Mutating

    /// @notice Borrow collateral tokens against locked issuance tokens
    /// @param requestedLoanAmount_ The amount of collateral tokens to borrow
    /// @return loanId_ The ID of the created loan
    function borrow(uint requestedLoanAmount_)
        external
        returns (uint loanId_);

    /// @notice Repay a specific loan by ID
    /// @param loanId_ The ID of the loan to repay
    /// @param repaymentAmount_ The amount to repay (if 0, repay the full loan)
    function repay(uint loanId_, uint repaymentAmount_) external;

    /// @notice Buy issuance tokens and borrow against them in a single transaction
    /// @param leverage_ The leverage multiplier for the borrowing (must be >= 1)
    /// @return loanId_ The ID of the created loan
    function buyAndBorrow(uint leverage_) external returns (uint loanId_);

    // =========================================================================
    // Public - Configuration (Lending Facility Manager only)

    /// @notice Set the borrowable quota
    /// @param newBorrowableQuota_ The new borrowable quota (in basis points)
    function setBorrowableQuota(uint newBorrowableQuota_) external;
}
