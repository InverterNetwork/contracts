// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";
import {Address} from "@oz/utils/Address.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

contract Beacon is IBeacon, ERC165, Ownable2Step {
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

        if (!Address.isContract(newImplementation)) {
            revert Beacon__ImplementationIsNotAContract();
        }

        _implementation = newImplementation;
    }

    //--------------------------------------------------------------------------------
    // ERC165 FUNCTIONS

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return interfaceId == type(IBeacon).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
