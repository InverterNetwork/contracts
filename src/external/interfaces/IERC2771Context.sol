// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IERC2771Context {
    /// @notice Returns the trusted forwarder for the EIP2771 Standard
    function isTrustedForwarder(address forwarder)
        external
        view
        returns (bool);
}
