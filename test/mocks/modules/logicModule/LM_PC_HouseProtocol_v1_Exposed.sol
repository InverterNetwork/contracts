// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {LM_PC_Lending_Facility_v1} from
    "src/modules/logicModule/LM_PC_Lending_Facility_v1.sol";

// Access Mock of the LM_PC_Lending_Facility_v1 contract for Testing.
contract LM_PC_Lending_Facility_v1_Exposed is LM_PC_Lending_Facility_v1 {
    // Use the `exposed_` prefix for functions to expose internal contract for
    // testing.

    function exposed_ensureValidBorrowAmount(uint amount_) external pure {
        _ensureValidBorrowAmount(amount_);
    }

    function exposed_calculateBorrowCapacity() external view returns (uint) {
        return _calculateBorrowCapacity();
    }

    function exposed_calculateUserBorrowingPower(address user_)
        external
        view
        returns (uint)
    {
        return _calculateUserBorrowingPower(user_);
    }

    function exposed_calculateDynamicBorrowingFee(uint requestedAmount_)
        external
        view
        returns (uint)
    {
        return _calculateDynamicBorrowingFee(requestedAmount_);
    }

    function exposed_calculateCollateralAmount(uint issuanceTokenAmount_)
        external
        view
        returns (uint)
    {
        return _calculateCollateralAmount(issuanceTokenAmount_);
    }

    function exposed_calculateRequiredIssuanceTokens(uint borrowAmount_)
        external
        view
        returns (uint)
    {
        return _calculateRequiredIssuanceTokens(borrowAmount_);
    }

    function exposed_getFloorPrice() external view returns (uint) {
        return _getFloorPrice();
    }

    function exposed_removeLoanFromUserLoans(address user_, uint loanId_)
        external
    {
        _removeLoanFromUserLoans(user_, loanId_);
    }

    function exposed_calculateIssuanceTokensToUnlockForLoan(
        Loan memory loan_,
        uint repaymentAmount_
    ) external pure returns (uint) {
        return _calculateIssuanceTokensToUnlockForLoan(loan_, repaymentAmount_);
    }
}
