// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {Ownable} from "@oz/access/Ownable.sol";

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

//Internal Interfaces
import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";
/**
 * @title Beacon
 */

contract InverterBeacon is IInverterBeacon, ERC165, Ownable2Step {
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
        return interfaceId == type(IInverterBeacon).interfaceId
            || interfaceId == type(IBeacon).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------------
    // State

    /// @dev The beacon's implementation address.
    address private _implementation;

    /// @dev the major version of the implementation
    uint majorVersion;

    /// @dev the minor version of the implementation
    uint minorVersion;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(uint _majorVersion) Ownable(_msgSender()) {
        majorVersion = _majorVersion;
    }

    //--------------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IBeacon
    function implementation() public view virtual override returns (address) {
        return _implementation;
    }

    /// @inheritdoc IInverterBeacon
    function version() external view returns (uint, uint) {
        return (majorVersion, minorVersion);
    }

    //--------------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @inheritdoc IInverterBeacon
    function upgradeTo(address newImplementation, uint newMinorVersion)
        public
        onlyOwner
    {
        if (newMinorVersion <= minorVersion) {
            revert Beacon__InvalidImplementationMinorVersion();
        }

        _setImplementation(newImplementation);

        minorVersion = newMinorVersion;

        emit Upgraded(newImplementation, newMinorVersion);
    }

    //--------------------------------------------------------------------------------
    // Internal Mutating Functions

    function _setImplementation(address newImplementation) private {
        if (!(newImplementation.code.length > 0)) {
            revert Beacon__InvalidImplementation();
        }

        _implementation = newImplementation;
    }
}
