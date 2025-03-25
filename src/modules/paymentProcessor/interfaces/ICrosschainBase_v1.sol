// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/// @title  ICrossChainBase_v1
/// @notice Base interface for cross-chain payment processing functionality
interface ICrossChainBase_v1 {
    // -------------------------------------------------------------------------
    // View Functions

    /// @notice Get the bridge data for a given payment ID.
    /// @param  paymentId_ The ID of the payment to get the bridge data for.
    /// @return bridgeData_ The bridge data for the given payment ID.
    function getBridgeData(uint paymentId_)
        external
        view
        returns (bytes memory bridgeData_);
}
