// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Types} from "src/common/Types.sol";

interface IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by activated module.
    error Proposal__ModuleManager__OnlyCallableByModule();

    /// @notice ModuleManager is already initialized.
    error Proposal__ModuleManager__AlreadyInitialized();

    /// @notice Execution of transaction requested by module failed.
    error Proposal__ModuleManager__ExecuteTxFromModuleFailed();

    /// @notice Given module address invalid.
    error Proposal__ModuleManager__InvalidModuleAddress();

    /// @notice Given module address already enabled.
    /// @param module The module address already enabled.
    error Proposal__ModuleManager__ModuleAlreadyEnabled(address module);

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when module enabled.
    event ModuleEnabled(address indexed module);

    /// @notice Event emitted when module disabled.
    event ModuleDisabled(address indexed module);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Executes a call to `to` with call data `data` either via call
    ///         or delegatecall.
    /// @dev Only callable by enabled modules.
    /// @param to The address to call.
    /// @param data The call data.
    /// @param operation The operation type. Either call or delegatecall.
    /// @return The return data of the call.
    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    ) external returns (bytes memory);

    /// @notice Returns whether the module `module` is enabled.
    /// @param module The module to check.
    /// @return True if module enabled, false otherwise.
    function isEnabledModule(address module) external returns (bool);
}
