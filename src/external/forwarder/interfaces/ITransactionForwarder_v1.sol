// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface ITransactionForwarder_v1 {
    //--------------------------------------------------------------------------
    // Structs

    struct SingleCall {
        address target; //Target contract that will receive the call
        bool allowFailure; //Is the call allowed to fail in the multicall execution
        bytes callData; //Data of the call
    }

    struct Result {
        bool success; //was the call a succes
        bytes returnData; //Return data of the call
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The request `from` doesn't match with the recovered `signer`.
    error CallFailed(SingleCall call);

    //--------------------------------------------------------------------------
    // Multicall Functions

    /// @notice Enables the execution of multiple calls in a single transaction
    /// @param calls Array of call structs that should be executed in the multicall
    /// @return returnData The return data of the calls that were executed
    function executeMulticall(SingleCall[] calldata calls)
        external
        returns (Result[] memory returnData);
}
