// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {PP_Streaming_v1} from "@pp/PP_Streaming_v1.sol";

contract PP_Streaming_v1AccessMock is PP_Streaming_v1 {
    //--------------------------------------------------------------------------
    // Getter Functions

    function getUnclaimableWalletIds(address client, address sender)
        public
        view
        returns (uint[] memory ids)
    {
        return unclaimableWalletIds[client][sender];
    }

    function getUnclaimableAmountForWalletIds(
        address client,
        address sender,
        uint id
    ) public view returns (uint amount) {
        return unclaimableAmountsForWalletId[client][sender][id];
    }

    //--------------------------------------------------------------------------
    // Internal Functions
}
