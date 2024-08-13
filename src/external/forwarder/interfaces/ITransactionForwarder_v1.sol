// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {ERC2771Forwarder} from "@oz/metatx/ERC2771Forwarder.sol";

interface ITransactionForwarder_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a single call.
    /// @param target Target contract that will receive the call.
    /// @param allowFailure Is the call allowed to fail in the multicall execution.
    /// @param callData Data of the call.
    struct SingleCall {
        address target;
        bool allowFailure;
        bytes callData;
    }

    /// @notice Struct used to store information about a call result.
    /// @param success Was the call a succes.
    /// @param returnData Return data of the call.
    struct Result {
        bool success;
        bytes returnData;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The request `from` doesn't match with the recovered `signer`.
    /// @param call The call that failed.
    error CallFailed(SingleCall call);

    //--------------------------------------------------------------------------
    // Metatransaction Helper Functions

    /// @notice Creates a digest for the given `ForwardRequestData`.
    /// @dev The signature field of the given `ForwardRequestData` can be empty.
    /// @param req The ForwardRequest you want to get the digest from.
    /// @return digest The digest needed to create a signature for the request.
    function createDigest(ERC2771Forwarder.ForwardRequestData memory req)
        external
        view
        returns (bytes32 digest);

    //--------------------------------------------------------------------------
    // Multicall Functions

    /// @notice Enables the execution of multiple calls in a single transaction.
    /// @param calls Array of call structs that should be executed in the multicall.
    /// @return returnData The return data of the calls that were executed.
    function executeMulticall(SingleCall[] calldata calls)
        external
        returns (Result[] memory returnData);
}
