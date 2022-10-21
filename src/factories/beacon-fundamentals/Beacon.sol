// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import "lib/openzeppelin-contracts/contracts/utils/Address.sol";

import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

contract Beacon is IBeacon, Ownable2Step {
    //--------------------------------------------------------------------------------
    // Error

    /// @notice The given ImplementationAddress is not a Contract
    error Beacon__ImplementationIsNotAContract();

    //--------------------------------------------------------------------------------
    // STATE

    address private _implementation;

    //--------------------------------------------------------------------------------
    // EVENTS

    /// @notice The beacon got upgraded to a new address
    event Upgraded(address indexed implementation);

    //--------------------------------------------------------------------------------
    // CONSTRUCTOR

    /// @inheritdoc IBeacon
    function implementation() public view virtual override returns (address) {
        return _implementation;
    }

    //--------------------------------------------------------------------------------
    // FUNCTIONS

    /// @notice upgrades the beacon to a new implementation address
    /// @param newImplementation : the new implementation address
    function upgradeTo(address newImplementation) public onlyOwner {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /// @notice sets the implementation address of the beacon
    /// @param newImplementation the new implementation address
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert Beacon__ImplementationIsNotAContract();
        }
        _implementation = newImplementation;
    }
}
