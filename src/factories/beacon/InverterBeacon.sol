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

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validNewMinorVersion(uint newMinorVersion) {
        // version is invalid if
        // - new number is less or equal to old (needs to be greater)
        // - the following conditions are NOT met
        //  - current minor version is set to 0
        //  - new minor version is set to 0
        //  - implementation is currently set to 0
        // The second clause allows us to set a version x.0,
        // but only if it's really the first implementation
        if (
            newMinorVersion <= minorVersion
                && !(
                    newMinorVersion == 0 && minorVersion == 0
                        && _implementationAddress == address(0)
                )
        ) {
            revert Beacon__InvalidImplementationMinorVersion();
        }
        _;
    }

    modifier validImplementation(address newImplementation) {
        if (!(newImplementation.code.length > 0)) {
            revert Beacon__InvalidImplementation();
        }
        _;
    }

    //--------------------------------------------------------------------------------
    // State

    /// @dev The beacon's implementation address.
    /// Can only be changed via the _setImplementation() function
    address internal _implementationAddress;

    /// @dev The beacon's current implementation pointer.
    /// In case of emergency can be set to address(0) to pause functionality
    address internal _implementationPointer;

    /// @dev Is the beacon shut down / in emergency mode
    bool internal _emergencyMode;

    /// @dev The major version of the implementation
    uint internal majorVersion;

    /// @dev The minor version of the implementation
    uint internal minorVersion;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(uint _majorVersion) Ownable(_msgSender()) {
        majorVersion = _majorVersion;
    }

    //--------------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IBeacon
    function implementation() public view virtual override returns (address) {
        return _implementationPointer;
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
    ) public onlyOwner validNewMinorVersion(newMinorVersion) {
        _setImplementation(newImplementation, overrideShutdown);

        minorVersion = newMinorVersion;

        emit Upgraded(newImplementation, newMinorVersion);
    }

    //--------------------------------------------------------------------------------
    // onlyOwner Intervention Mechanism

    /// @inheritdoc IInverterBeacon
    function shutDownImplementation() external onlyOwner {
        //Go into emergency mode
        _emergencyMode = true;
        //Set implementation pointer to address 0 and therefor halting the system
        _implementationPointer = address(0);

        emit ShutdownInitiated();
    }

    /// @inheritdoc IInverterBeacon
    function restartImplementation() external onlyOwner {
        //Reverse emergency mode
        _emergencyMode = false;
        //Set implementation pointer back to original implementation address
        _implementationPointer = _implementationAddress;

        emit ShutdownReversed();
    }

    //--------------------------------------------------------------------------------
    // Internal Mutating Functions

    function _setImplementation(
        address newImplementation,
        bool overrideShutdown
    ) internal virtual validImplementation(newImplementation) {
        _implementationAddress = newImplementation;

        //If the beacon is running normally
        if (!_emergencyMode) {
            //Change the _implementationPointer accordingly
            _implementationPointer = newImplementation;
        } else {
            //If emergencyMode is active and overrideShutdown is true
            if (overrideShutdown) {
                //Change the _implementationPointer accordingly
                _implementationPointer = newImplementation;
                //And reverse emergency Mode
                _emergencyMode = false;

                emit ShutdownReversed();
            }
        }
    }
}
