// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Interfaces
import {IERC2771Context} from "src/external/interfaces/IERC2771Context.sol";

interface IModuleManagerBase_v1 is IERC2771Context {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error ModuleManagerBase_v1__CallerNotAuthorized();

    /// @notice Function is only callable by modules.
    error ModuleManagerBase_v1__OnlyCallableByModule();

    /// @notice Given module address invalid.
    error ModuleManagerBase_v1__InvalidModuleAddress();

    /// @notice Given address is a module.
    error ModuleManagerBase_v1__IsModule();

    /// @notice Given address is not a module.
    error ModuleManagerBase_v1__IsNotModule();

    /// @notice The supplied modules are not consecutive.
    error ModuleManagerBase_v1__ModulesNotConsecutive();

    /// @notice The Manager has reached the maximum amount of modules.
    error ModuleManagerBase_v1__ModuleAmountOverLimits();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when module added.
    /// @param module The module's address.
    event ModuleAdded(address indexed module);

    /// @notice Event emitted when module removed.
    /// @param module The module's address.
    event ModuleRemoved(address indexed module);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Executes a call to `to` with call data `data` either via call
    /// @dev Only callable by enabled modules.
    /// @param to The address to call.
    /// @param data The call data.
    /// @return Whether the call succeeded.
    /// @return The return data of the call.
    function executeTxFromModule(address to, bytes memory data)
        external
        returns (bool, bytes memory);

    /// @notice Adds address `module` as module.
    /// @dev Only callable by authorized address.
    /// @dev Fails if address invalid or address already added as module.
    /// @param module The module address to add.
    function addModule(address module) external;

    /// @notice Removes address `module` as module.
    /// @dev Only callable by authorized address.
    /// @dev Fails if address not added as module.
    /// @param module The module address to remove.
    function removeModule(address module) external;

    /// @notice Returns whether the address `module` is added as module.
    /// @param module The module to check.
    /// @return True if module added, false otherwise.
    function isModule(address module) external returns (bool);

    /// @notice Returns the list of all modules.
    /// @return List of all modules.
    function listModules() external view returns (address[] memory);

    /// @notice Returns the number of modules.
    function modulesSize() external view returns (uint8);

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable
    // @dev We imitate here the EIP2771 Standard to enable metatransactions

    // @notice Returns wether the given address is the trusted forwarder or not
    // @dev Exposes the ERC2771 isTrusted Forwarder
    function isTrustedForwarder(address forwarder)
        external
        view
        returns (bool);

    // @notice Returns the trusted forwarder for metatransactions
    // @dev Exposes the ERC2771 isTrusted Forwarder
    function trustedForwarder() external view returns (address);
}
