// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @dev Library providing error types for OpenZeppelin contracts.
 */
library OZErrors {
    // Contract: Initializable
    bytes4 public constant Initializable__NotInitializing =
        bytes4(keccak256("NotInitializing()"));
    bytes4 internal constant Initializable__InvalidInitialization =
        bytes4(keccak256("InvalidInitialization()"));

    // Contract: Ownable
    bytes4 internal constant Ownable__UnauthorizedAccount =
        bytes4(keccak256("OwnableUnauthorizedAccount(address)"));

}
