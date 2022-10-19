// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import "lib/openzeppelin-contracts/contracts/utils/Address.sol";

import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

contract Beacon is IBeacon, Ownable2Step {
    //@note Do we need some identifier for a module here?
    address private _implementation;

    /// @notice The beacon got upgraded to a new address
    event Upgraded(address indexed implementation);

    /// @inheritdoc IBeacon
    function implementation() public view override returns (address) {
        return _implementation;
    }

    /// @notice upgrades the beacon to a new implementation address
    /// @param newImplementation : the new implementation address
    function upgradeTo(address newImplementation) public onlyOwner {// @todo value check
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /// @notice sets the implementation address of the beacon
    /// @param newImplementation the new implementation address
    function _setImplementation(address newImplementation) private {
        require(
            Address.isContract(newImplementation),
            "UpgradeableBeacon: implementation is not a contract"// @todo Error
        );
        _implementation = newImplementation;
    }
}
