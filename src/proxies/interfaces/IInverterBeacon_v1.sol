// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

interface IInverterBeacon_v1 is IBeacon {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given implementation invalid.
    error InverterBeacon__InvalidImplementation();

    /// @notice Given implementation minor and patch version is not higher than previous minor version.
    error InverterBeacon__InvalidImplementationMinorOrPatchVersion();

    //--------------------------------------------------------------------------
    // Events

    /// @notice The {InverterBeacon_v1} was constructed.
    /// @param majorVersion The majorVersion of the implementation contract.
    event Constructed(uint majorVersion);

    /// @notice The {InverterBeacon_v1} was upgraded to a new implementation address.
    /// @param implementation The new implementation address.
    /// @param newMinorVersion The new minor version of the implementation contract.
    /// @param newPatchVersion The new patch version of the implementation contract.
    event Upgraded(
        address indexed implementation,
        uint newMinorVersion,
        uint newPatchVersion
    );

    /// @notice The {InverterBeacon_v1} shutdown was initiated.
    event ShutdownInitiated();

    /// @notice The {InverterBeacon_v1} shutdown was reversed.
    event ShutdownReversed();

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @notice Returns the version of the linked implementation.
    /// @return Major version.
    /// @return Minor version.
    /// @return Patch version.
    function version() external view returns (uint, uint, uint);

    /// @notice Returns the {InverterReverter_v1} of the {InverterBeacon_v1}.
    /// @return ReverterAddress The address of the reverter contract.
    function getReverterAddress() external returns (address);

    /// @notice Returns the implementation address of the {InverterBeacon_v1}.
    /// @return ImplementationAddress The address of the implementation.
    function getImplementationAddress() external returns (address);

    /// @notice Returns wether the {InverterBeacon_v1} is in emergency mode or not.
    /// @return emergencyModeActive Is the beacon in emergency mode.
    function emergencyModeActive() external view returns (bool);

    //--------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @notice Upgrades the {InverterBeacon_v1} to a new implementation address.
    /// @dev	Only callable by owner.
    /// @dev	`overrideShutdown` Doesnt do anything if {InverterBeacon_v1} is not in emergency mode.
    /// @dev	Revert if new implementation invalid.
    /// @param newImplementation The new implementation address.
    /// @param newMinorVersion The new minor version of the implementation contract.
    /// @param newPatchVersion The new patch version of the implementation contract.
    /// @param overrideShutdown Flag to enable upgradeTo function to override the shutdown.
    function upgradeTo(
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion,
        bool overrideShutdown
    ) external;

    //--------------------------------------------------------------------------
    // onlyOwner Intervention Mechanism

    /// @notice Shuts down the {InverterBeacon_v1} and stops the system.
    /// @dev	Only callable by owner.
    /// @dev	Changes the implementation address to address(0).
    function shutDownImplementation() external;

    /// @notice Restarts the {InverterBeacon_v1} and the system.
    /// @dev	Only callable by owner.
    /// @dev	Changes the implementation address from address(0) to the original implementation.
    function restartImplementation() external;
}
