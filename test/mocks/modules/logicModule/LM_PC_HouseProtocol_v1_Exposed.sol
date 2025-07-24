// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {LM_PC_HouseProtocol_v1} from
    "src/modules/logicModule/LM_PC_HouseProtocol_v1.sol";

// Access Mock of the LM_PC_HouseProtocol_v1 contract for Testing.
contract LM_PC_HouseProtocol_v1_Exposed is LM_PC_HouseProtocol_v1 {
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

    function exposed_calculateIssuanceTokensToUnlock(
        address user_,
        uint repaymentAmount_
    ) external view returns (uint) {
        return _calculateIssuanceTokensToUnlock(user_, repaymentAmount_);
    }
}
