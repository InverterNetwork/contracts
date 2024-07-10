// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

// External Dependencies
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title   Inverter Beacon
 *
 * @notice  Manages upgrades and versioning for smart contract implementations, allowing
 *          contract administrators to dynamically change contract logic while maintaining
 *          the state. Supports emergency shutdown mechanisms to halt operations if needed.
 *
 * @dev     Extends {ERC165} for interface detection and implements both {IInverterBeacon_v1} and
 *          {IBeacon}. Uses modifiers to enforce constraints on implementation upgrades. Unique
 *          features include emergency mode control and strict version handling with major,
 *          minor and patch version concepts.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract InverterBeacon_v1 is IInverterBeacon_v1, ERC165, Ownable2Step {
    //--------------------------------------------------------------------------
    // ERC-165 Public View Functions

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return interfaceId == type(IInverterBeacon_v1).interfaceId
            || interfaceId == type(IBeacon).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validImplementation(address newImplementation) {
        if (!(newImplementation.code.length > 0)) {
            revert InverterBeacon__InvalidImplementation();
        }
        _;
    }

    modifier validNewMinorOrPatchVersion(
        uint newMinorVersion,
        uint newPatchVersion
    ) {
        if (
            // Minor Version cant go down
            newMinorVersion < minorVersion
            // Patch Version cant go down or stay the same if minorVersion stays the same
            || newPatchVersion <= patchVersion
                && newMinorVersion == minorVersion
        ) {
            revert InverterBeacon__InvalidImplementationMinorOrPatchVersion();
        }
        _;
    }

    //--------------------------------------------------------------------------
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

    /// @dev The patch version of the implementation
    uint internal patchVersion;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(
        address owner,
        uint _majorVersion,
        address _implementation,
        uint _newMinorVersion,
        uint _newPatchVersion
    ) Ownable(owner) {
        majorVersion = _majorVersion;

        _upgradeTo(_implementation, _newMinorVersion, _newPatchVersion, false);
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IBeacon
    function implementation() public view virtual override returns (address) {
        return _implementationPointer;
    }

    /// @inheritdoc IInverterBeacon_v1
    function getImplementationAddress()
        external
        view
        virtual
        returns (address)
    {
        return _implementationAddress;
    }

    /// @inheritdoc IInverterBeacon_v1
    function emergencyModeActive() external view returns (bool) {
        return _emergencyMode;
    }

    /// @inheritdoc IInverterBeacon_v1
    function version() external view returns (uint, uint, uint) {
        return (majorVersion, minorVersion, patchVersion);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @inheritdoc IInverterBeacon_v1
    function upgradeTo(
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion,
        bool overrideShutdown
    )
        public
        onlyOwner
        validNewMinorOrPatchVersion(newMinorVersion, newPatchVersion)
    {
        _upgradeTo(
            newImplementation,
            newMinorVersion,
            newPatchVersion,
            overrideShutdown
        );
    }

    //--------------------------------------------------------------------------
    // onlyOwner Intervention Mechanism

    /// @inheritdoc IInverterBeacon_v1
    function shutDownImplementation() external onlyOwner {
        // Go into emergency mode
        _emergencyMode = true;
        // Set implementation pointer to address 0 and therefor halting the system
        _implementationPointer = address(0);

        emit ShutdownInitiated();
    }

    /// @inheritdoc IInverterBeacon_v1
    function restartImplementation() external onlyOwner {
        // Reverse emergency mode
        _emergencyMode = false;
        // Set implementation pointer back to original implementation address
        _implementationPointer = _implementationAddress;

        emit ShutdownReversed();
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _upgradeTo(
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion,
        bool overrideShutdown
    ) internal {
        _setImplementation(newImplementation, overrideShutdown);

        minorVersion = newMinorVersion;
        patchVersion = newPatchVersion;

        emit Upgraded(newImplementation, newMinorVersion, newPatchVersion);
    }

    function _setImplementation(
        address newImplementation,
        bool overrideShutdown
    ) internal virtual validImplementation(newImplementation) {
        _implementationAddress = newImplementation;

        // If the beacon is running normally
        if (!_emergencyMode) {
            // Change the _implementationPointer accordingly
            _implementationPointer = newImplementation;
        } else {
            // If emergencyMode is active and overrideShutdown is true
            if (overrideShutdown) {
                // Change the _implementationPointer accordingly
                _implementationPointer = newImplementation;
                // And reverse emergency Mode
                _emergencyMode = false;

                emit ShutdownReversed();
            }
        }
    }
}
