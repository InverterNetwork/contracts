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

    /// @notice Event emitted when account `account` is granted role `role` for
    ///         module `module`.
    event ModuleRoleGranted(
        address indexed module, bytes32 indexed role, address indexed account
    );

    /// @notice Event emitted when account `account` is revoked role `role` for
    ///         module `module`.
    event ModuleRoleRevoked(
        address indexed module, bytes32 indexed role, address indexed account
    );

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

    /// @notice Grants role `role` to account `account` in caller's access
    ///         control context.
    /// @dev Only callable by enabled module.
    /// @param role The access control role.
    /// @param account The account to grant given role.
    function grantRole(bytes32 role, address account) external;

    /// @notice Revokes role `role` from account `account` in caller's access
    ///         control context.
    /// @dev Only callable by enabled module.
    /// @param role The access control role.
    /// @param account The account to revoke role for.
    function revokeRole(bytes32 role, address account) external;

    /// @notice Renounces the caller's role `role` in module's `module` access
    ///         control context.
    /// @param module The module in which's access control context the role
    ///               should be renounced.
    /// @param role The access control role.
    function renounceRole(address module, bytes32 role) external;

    /// @notice Returns whether the account `account` holds the role `role` in
    ///         the module's `module` access control context.
    /// @param module The module in which's access control context the role
    ///               is checked.
    /// @param role The access control role.
    /// @param account The account to check role for.
    /// @return True if account has role in module's access control context,
    ///         false otherwise.
    function hasRole(address module, bytes32 role, address account)
        external
        returns (bool);

    /// @notice Returns whether the module `module` is enabled.
    /// @param module The module to check.
    /// @return True if module enabled, false otherwise.
    function isEnabledModule(address module) external returns (bool);
}
