// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

interface IInverterBeacon_v1 is IBeacon {
    //--------------------------------------------------------------------------------
    // Errors

    /// @notice Given implementation invalid.
    error InverterBeacon__InvalidImplementation();

    /// @notice Given implementation minor version is not higher than previous minor version.
    error InverterBeacon__InvalidImplementationMinorVersion();

    //--------------------------------------------------------------------------
    // Events

    /// @notice The Beacon was constructed.
    /// @param majorVersion The majorVersion of the implementation contract
    event Constructed(uint majorVersion);

    /// @notice The Beacon was upgraded to a new implementation address.
    /// @param implementation The new implementation address.
    /// @param newMinorVersion The new minor version of the implementation contract.
    event Upgraded(address indexed implementation, uint newMinorVersion);

    /// @notice The Beacon shutdown was initiated.
    event ShutdownInitiated();

    /// @notice The Beacon shutdown was reversed.
    event ShutdownReversed();

    //--------------------------------------------------------------------------------
    // Public View Functions

    /// @notice Returns the version of the linked implementation.
    /// @return The major version.
    /// @return The minor version.
    function version() external view returns (uint, uint);

    /// @notice Returns wether the beacon is in emergency mode or not.
    /// @return Is the beacon in emergency mode.
    function emergencyModeActive() external view returns (bool);

    //--------------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @notice Upgrades the beacon to a new implementation address.
    /// @dev Only callable by owner.
    /// @dev overrideShutdown Doesnt do anything if Beacon is not in emergency mode
    /// @dev Revert if new implementation invalid.
    /// @param newImplementation The new implementation address.
    /// @param overrideShutdown Flag to enable upgradeTo function to override the shutdown.
    function upgradeTo(
        address newImplementation,
        uint newMinorVersion,
        bool overrideShutdown
    ) external;

    //--------------------------------------------------------------------------------
    // onlyOwner Intervention Mechanism

    /// @notice Shuts down the beacon and stops the system
    /// @dev Only callable by owner.
    /// @dev Changes the implementation address to address(0)
    function shutDownImplementation() external;

    /// @notice Restarts the beacon and the system
    /// @dev Only callable by owner.
    /// @dev Changes the implementation address from address(0) to the original implementation
    function restartImplementation() external;
}
