// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Types} from "src/common/Types.sol";

interface IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Proposal__ModuleManager__CallerNotAuthorized();

    /// @notice Function is only callable by modules.
    error Proposal__ModuleManager__OnlyCallableByModule();

    /// @notice Given module address invalid.
    error Proposal__ModuleManager__InvalidModuleAddress();

    /// @notice Given address is a module.
    error Proposal__ModuleManager__IsModule();

    /// @notice Given address is not a module.
    error Proposal__ModuleManager__IsNotModule();

    /// @notice The supplied modules are not consecutive.
    error Proposal__ModuleManager__ModulesNotConsecutive();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when module added.
    /// @param module The module's address.
    event ModuleAdded(address indexed module);

    /// @notice Event emitted when module removed.
    /// @param module The module's address.
    event ModuleRemoved(address indexed module);

    /// @notice Event emitted when account `account` is granted role `role` for
    ///         module `module`.
    /// @param module The module's address.
    /// @param role The access control role.
    /// @param account The account the role was granted to.
    event ModuleRoleGranted(
        address indexed module, bytes32 indexed role, address indexed account
    );

    /// @notice Event emitted when account `account` is revoked role `role` for
    ///         module `module`.
    /// @param module The module's address.
    /// @param role The access control role.
    /// @param account The account the role was revoked for.
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
    /// @return Whether the call succeeded.
    /// @return The return data of the call.
    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    ) external returns (bool, bytes memory);

    /// @notice Adds address `module` as module.
    /// @dev Only callable by authorized address.
    /// @dev Fails if address invalid or address already added as module.
    /// @param module The module address to add.
    function addModule(address module) external;

    /// @notice Removes address `module` as module.
    /// @dev Only callable by authorized address.
    /// @dev Fails if address not added as module.
    /// @param module The module address to remove.
    function removeModule(address prevModule, address module) external;

    /// @notice Returns whether the address `module` is added as module.
    /// @param module The module to check.
    /// @return True if module added, false otherwise.
    function isModule(address module) external returns (bool);

    /// @notice Returns the list of all modules.
    /// @return List of all modules.
    function listModules() external view returns (address[] memory);

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
}
