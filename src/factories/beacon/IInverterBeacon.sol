// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

// Internal Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";

interface IInverterBeacon is IBeacon {
    //--------------------------------------------------------------------------------
    // Errors

    /// @notice Given implementation invalid.
    error Beacon__InvalidImplementation();

    /// @notice Given implementation minor version is not higher than previous minor version.
    error Beacon__InvalidImplementationMinorVersion();

    //--------------------------------------------------------------------------
    // Events

    /// @notice The Beacon was constructed.
    /// @param majorVersion The majorVersion of the implementation contract
    event Constructed(uint majorVersion);

    /// @notice The Beacon was upgraded to a new implementation address.
    /// @param implementation The new implementation address.
    /// @param newMinorVersion The new minor version of the implementation contract.
    event Upgraded(address indexed implementation, uint newMinorVersion);

    //--------------------------------------------------------------------------------
    // Public View Functions

    /// @notice Returns the version of the linked implementation.
    /// @return The major version.
    /// @return The minor version.
    function version() external view returns (uint, uint);

    //--------------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @notice Upgrades the beacon to a new implementation address.
    /// @dev Only callable by owner.
    /// @dev Revert if new implementation invalid.
    /// @param newImplementation The new implementation address.
    function upgradeTo(address newImplementation, uint newMinorVersion)
        external;
}
