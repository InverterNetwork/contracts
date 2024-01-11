// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

// External Dependencies
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {Ownable} from "@oz/access/Ownable.sol";


// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

/**
 * @title Beacon
 */
contract Beacon is IBeacon, ERC165, Ownable2Step {
    //--------------------------------------------------------------------------------
    // Errors

    /// @notice Given implementation invalid.
    error Beacon__InvalidImplementation();

    //--------------------------------------------------------------------------------
    // Events

    /// @notice Beacon upgraded to new implementation address.
    event Upgraded(address indexed implementation);

    //--------------------------------------------------------------------------------
    // State

    /// @dev The beacon's implementation address.
    address private _implementation;

    //--------------------------------------------------------------------------
    // Constructor

    constructor() Ownable(_msgSender()) {
    }

    //--------------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IBeacon
    function implementation() public view virtual override returns (address) {
        return _implementation;
    }

    //--------------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @notice Upgrades the beacon to a new implementation address.
    /// @dev Only callable by owner.
    /// @dev Revert if new implementation invalid.
    /// @param newImplementation The new implementation address.
    function upgradeTo(address newImplementation) public onlyOwner {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    //--------------------------------------------------------------------------------
    // Internal Mutating Functions

    function _setImplementation(address newImplementation) private {
        if (!(newImplementation.code.length > 0)) {
            revert Beacon__InvalidImplementation();
        }

        _implementation = newImplementation;
    }

    //--------------------------------------------------------------------------------
    // ERC-165 Public View Functions

    /// @inheritdoc ERC165
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
