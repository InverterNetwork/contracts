// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @dev Library providing error types for OpenZeppelin contracts.
 */
library OZErrors {
    // Contract: Initializable
    bytes public constant Initializable__NotInitializing =
        bytes("Initializable: contract is not initializing");
    bytes internal constant Initializable__AlreadyInitialized =
        bytes("Initializable: contract is already initialized");

    // Contract: Ownable2Step (inherits the error from Ownable)
    bytes internal constant Ownable2Step__CallerNotOwner =
        bytes("Ownable: caller is not the owner");
}
