// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Dependencies
import {Proxy} from "@oz/proxy/Proxy.sol";

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

/**
 * @title BeaconProxy
 */
contract BeaconProxy is Proxy {
    //--------------------------------------------------------------------------------
    // Events

    /// @notice Proxy upgraded to new {IBeacon} instance.
    event BeaconUpgraded(IBeacon indexed beacon);

    //--------------------------------------------------------------------------------
    // State

    /// @notice {IBeacon} instance that points to the implementation.
    IBeacon private immutable _beacon;

    //--------------------------------------------------------------------------------
    // Constructor

    /// @notice Constructs the BeaconProxy.
    /// @dev Sets the {IBeacon} instance that contains the implementation address.
    /// @param beacon The {IBeacon} instance.
    constructor(IBeacon beacon) {
        _beacon = beacon;
        emit BeaconUpgraded(beacon);
    }

    //--------------------------------------------------------------------------------
    // Internal View Functions

    /// @inheritdoc Proxy
    function _implementation() internal view override returns (address) {
        return _beacon.implementation();
    }
}
