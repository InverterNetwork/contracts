// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {LM_PC_Bounties_v2} from "@lm/LM_PC_Bounties_v2.sol";

contract LM_PC_Bounties_v2AccessMock is LM_PC_Bounties_v2 {
    //--------------------------------------------------------------------------
    // Modifier Access

    function validArrayLengthsCheck(
        uint minimumPayoutAmountLength,
        uint maximumPayoutAmountLength,
        uint detailArrayLength
    )
        external
        pure
        validArrayLengths(
            minimumPayoutAmountLength,
            maximumPayoutAmountLength,
            detailArrayLength
        )
    {}

    //--------------------------------------------------------------------------
    // Internal Functions

    function direct__validPayoutAmounts(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount
    ) external pure {
        _validPayoutAmounts(minimumPayoutAmount, maximumPayoutAmount);
    }

    function direct__addBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    ) external returns (uint) {
        return _addBounty(minimumPayoutAmount, maximumPayoutAmount, details);
    }
}
