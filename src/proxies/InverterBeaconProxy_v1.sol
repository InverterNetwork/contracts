// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// External Dependencies
import {Proxy} from "@oz/proxy/Proxy.sol";

/**
 * @title   InverterBeaconProxy_v1: Beacon Proxy for Implementation Upgrades for the Inverter Network.
 *
 * @notice  Acts as a proxy for Inverter Network's smart contracts, allowing for upgrades
 *          to contract implementations without affecting the existing state or contract
 *          addresses, thereby achieving upgradeable contracts.
 *
 * @dev     Implements the Proxy pattern by referencing the {InverterBeacon_v1}, which holds
 *          the address of the current implementation to which calls are delegated.
 *
 * @author  Inverter Network.
 */
contract InverterBeaconProxy_v1 is Proxy {
    //--------------------------------------------------------------------------------
    // Events

    /// @notice Proxy upgraded to new {InverterBeacon_v1} instance.
    /// @param beacon The new {InverterBeacon_v1} instance.
    event BeaconUpgraded(IInverterBeacon_v1 indexed beacon);

    //--------------------------------------------------------------------------------
    // State

    /// @notice {InverterBeacon_v1} instance that points to the implementation.
    IInverterBeacon_v1 private immutable _beacon;

    //--------------------------------------------------------------------------------
    // Constructor

    /// @notice Constructs the InverterBeaconProxy_v1.
    /// @dev Sets the {InverterBeacon_v1} instance that contains the implementation address.
    /// @param beacon The {InverterBeacon_v1} instance.
    constructor(IInverterBeacon_v1 beacon) {
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
