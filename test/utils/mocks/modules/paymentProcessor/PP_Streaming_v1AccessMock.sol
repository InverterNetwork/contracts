// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {PP_Streaming_v1} from "@pp/PP_Streaming_v1.sol";

contract PP_Streaming_v1AccessMock is PP_Streaming_v1 {
    //--------------------------------------------------------------------------
    // Getter Functions

    function getUnclaimableStreams(
        address client,
        address token,
        address sender
    ) public view returns (uint[] memory ids) {
        return unclaimableStreams[client][token][sender];
    }

    function getUnclaimableAmountForStreams(
        address client,
        address token,
        address sender,
        uint id
    ) public view returns (uint amount) {
        return unclaimableAmountsForStream[client][token][sender][id];
    }

    function getValidTimes(uint _start, uint _cliff, uint _end)
        public
        pure
        returns (bool)
    {
        return validTimes(_start, _cliff, _end);
    }

    //--------------------------------------------------------------------------
    // Internal Functions
}
