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

    /// @dev The beacon's current implementation pointer.
    address private _currentImplementation;

    /// @dev Is the beacon shut down / in emergency mode
    bool public _emergencyMode;

    /// @dev The major version of the implementation
    uint private majorVersion;

    /// @dev The minor version of the implementation
    uint private minorVersion;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(uint _majorVersion) Ownable(_msgSender()) {
        majorVersion = _majorVersion;
    }

    //--------------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IBeacon
    function implementation() public view virtual override returns (address) {
        return _currentImplementation;
    }

    /// @inheritdoc IInverterBeacon
    function emergencyModeActive() external view returns (bool) {
        return _emergencyMode;
    }

    /// @inheritdoc IInverterBeacon
    function version() external view returns (uint, uint) {
        return (majorVersion, minorVersion);
    }

    //--------------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @inheritdoc IInverterBeacon
    function upgradeTo(
        address newImplementation,
        uint newMinorVersion,
        bool overrideShutdown
    ) public onlyOwner {
        if (newMinorVersion <= minorVersion) {
            revert Beacon__InvalidImplementationMinorVersion();
        }

        _setImplementation(newImplementation, overrideShutdown);

        minorVersion = newMinorVersion;

        emit Upgraded(newImplementation, newMinorVersion);
    }

    //--------------------------------------------------------------------------------
    // onlyOwner Intervention Mechanism

    /// @inheritdoc IInverterBeacon
    function shutdownImplementation() external {
        //Go into emergency mode
        _emergencyMode = true;
        //Set Implementation to address 0 and therefor halting the system
        _currentImplementation = address(0);

        emit ShutdownInitiated();
    }

    /// @inheritdoc IInverterBeacon
    function restartImplementation() external {
        //Reverse emergency mode
        _emergencyMode = false;
        //Set Implementation back to original implementation
        _currentImplementation = _implementation;

        emit ShutdownReversed();
    }

    //--------------------------------------------------------------------------------
    // Internal Mutating Functions

    function _setImplementation(
        address newImplementation,
        bool overrideShutdown
    ) private {
        if (!(newImplementation.code.length > 0)) {
            revert Beacon__InvalidImplementation();
        }

        _implementation = newImplementation;

        //If the beacon is running normally
        if (!_emergencyMode) {
            //Change the _currentImplementation accordingly
            _currentImplementation = newImplementation;
        } else {
            //If emergencyMode is active and overrideShutdown is true
            if (overrideShutdown) {
                //Change the _currentImplementation accordingly
                _currentImplementation = newImplementation;
                //And reverse emergency Mode
                _emergencyMode = false;

                emit ShutdownReversed();
            }
        }
    }
}
