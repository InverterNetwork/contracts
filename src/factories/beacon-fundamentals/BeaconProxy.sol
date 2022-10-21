// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import "lib/openzeppelin-contracts/contracts/proxy/Proxy.sol";

/// @custom:security-contact security@p00ls.com
contract BeaconProxy is Proxy {
    //--------------------------------------------------------------------------------
    // STATE

    /// @notice The beacon that points to the implementation
    IBeacon private immutable _beacon;

    //--------------------------------------------------------------------------------
    // EVENTS

    /// @notice the proxy upgraded to a new beacon
    event BeaconUpgraded(IBeacon indexed beacon);

    //--------------------------------------------------------------------------------
    // CONSTRUCTOR

    /// @notice Construct the BeaconProxy
    /// @dev Sets the beacon address that contains the implementation address
    /// @param beacon the according beacon address
    constructor(IBeacon beacon) {
        _beacon = beacon;
        emit BeaconUpgraded(beacon);
    }

    //--------------------------------------------------------------------------------
    // FUNCTIONS

    /// @inheritdoc Proxy
    function _implementation() internal view override returns (address) {
        return _beacon.implementation();
    }
}
