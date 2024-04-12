// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {Proxy} from "@oz/proxy/Proxy.sol";

// Internal Dependencies
import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

/**
 * @title BeaconProxy
 */
contract InverterBeaconProxy is Proxy {
    //--------------------------------------------------------------------------------
    // Events

    /// @notice Proxy upgraded to new {InverterBeacon} instance.
    /// @param beacon The new {InverterBeacon} instance.
    event BeaconUpgraded(IInverterBeacon indexed beacon);

    //--------------------------------------------------------------------------------
    // State

    /// @notice {InverterBeacon} instance that points to the implementation.
    IInverterBeacon private immutable _beacon;

    //--------------------------------------------------------------------------------
    // Constructor

    /// @notice Constructs the InverterBeaconProxy.
    /// @dev Sets the {InverterBeacon} instance that contains the implementation address.
    /// @param beacon The {InverterBeacon} instance.
    constructor(IInverterBeacon beacon) {
        _beacon = beacon;
        emit BeaconUpgraded(beacon);
    }

    //--------------------------------------------------------------------------------
    // Public View Functions

    /// @dev This overrides the possible use of a "version" function in the modules that are called via the Proxy Beacon structure
    /// @notice Returns the version of the linked implementation.
    /// @return The major version.
    /// @return The minor version.
    function version() external view returns (uint, uint) {
        return _beacon.version();
    }

    //--------------------------------------------------------------------------------
    // Internal View Functions

    /// @inheritdoc Proxy
    function _implementation() internal view override returns (address) {
        return _beacon.implementation();
    }
}
