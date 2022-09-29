// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

library OZErrors {
    // Contract: Initializable
    bytes public constant Initializable__NotInitializing =
        bytes("Initializable: contract is not initializing");
    bytes internal constant Initializable__AlreadyInitialized =
        bytes("Initializable: contract is already initialized");
}
