// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessManager} from "@oz/access/manager/IAccessManager.sol";
import {IModule_v2} from "src/modules/base/IModule_v2.sol";

interface IAuthorizer_v2 is IAccessManager {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a role is transferred.
    /// @param roleId_ The role id.
    /// @param sender_ The sender of the role transfer.
    /// @param newHolder_ The new holder of the role.
    event RoleTransferred(uint64 roleId_, address sender_, address newHolder_);

    /// @notice Emitted when the role transferable flag is set.
    /// @param roleId_ The role id.
    /// @param transferable_ The transferable flag.
    event RoleTransferable(uint64 roleId_, bool transferable_);

    /// @notice Emitted when the module admin role id is set.
    /// @param target_ The target address.
    /// @param newModuleAdminId_ The new module admin role id.
    event NewModuleAdminRoleId(address target_, uint64 newModuleAdminId_);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by a workflow admin.
    error Authorizer_v2__OnlyCallableByWorkflowAdmin();

    /// @notice Function is only callable by a module or the admin.
    error Authorizer_v2__OnlyCallableByModuleOrAdmin();

    /// @notice Function is only callable by a module admin.
    error Authorizer_v2__OnlyCallableByModuleAdmin();

    /// @notice The given RoleId has not been created yet.
    error Authorizer_v2__RoleIdNotCreated();

    /// @notice The given RoleId is not transferable.
    error Authorizer_v2__RoleNotTransferable();

    //--------------------------------------------------------------------------
    // Public Getter Functions

    /// @notice Returns the next role id that will be created.
    /// @return currentRoleId_ The next role if that will be created.
    function getCurrentRoleId() external view returns (uint64 currentRoleId_);

    /// @notice Returns the role transferable flag.
    /// @dev    This is restricted to existing roles.
    /// @param  roleId_ The role id.
    /// @return transferable_ The transferable flag.
    function getRoleTransferable(uint64 roleId_)
        external
        view
        returns (bool transferable_);

    //--------------------------------------------------------------------------
    // Public Mutating General Functions

    /// @notice Transfers a role to a new holder.
    /// @dev    This is restricted to existing roles and to roles that are
    ///         transferable.
    /// @dev    This is restricted existing roles.
    /// @dev    This emits a {RoleTransferred} event.
    /// @param  roleId_ The role id.
    /// @param  newHolder_ The new holder of the role.
    function transferRole(uint64 roleId_, address newHolder_) external;

    //--------------------------------------------------------------------------
    // Public Mutating Admin Functions

    /// @notice Creates a role, links the specified function selectors to that
    ///         role and adds the specified role holders to the role
    /// @dev    This is restricted to the admin and to modules that are registered
    ///         in the orchestrator.
    /// @param  target_ The target contract where the role will be specified in.
    /// @param  roleSpec_ The Specifications to the role that will be created.
    /// @return roleId_ The id of the created role.
    function createRoleWithSpecifications(
        address target_,
        IModule_v2.RoleSpecification memory roleSpec_
    ) external returns (uint64 roleId_);

    /// @notice Creates a new role and links it to the given name via event.
    /// @dev    This is restricted to the admin and to modules that are registered
    ///         in the orchestrator.
    /// @param  roleName_ The name of the role to be created.
    /// @return roleId_ The id of the created role.
    function createRole(string memory roleName_)
        external
        returns (uint64 roleId_);

    /// @notice Sets the role transferable flag.
    /// @dev    This is restricted to the admin and to modules that are registered
    ///         in the orchestrator.
    /// @dev    This is restricted to existing roles.
    /// @dev    This emits a {RoleTransferable} event.
    /// @param  roleId_ The role id.
    /// @param  transferable_ The transferable flag.
    function setRoleTransferable(uint64 roleId_, bool transferable_) external;

    /// @notice Sets the module admin role id.
    /// @dev    This is restricted to the workflow admin.
    /// @dev    This is restricted to existing modules.
    /// @dev    This emits a {NewModuleAdminRoleId} event.
    /// @param  target_ The target address.
    /// @param  newModuleAdminId_ The new module admin role id.
    function setModuleAdminRoleId(address target_, uint64 newModuleAdminId_)
        external;

    /// @notice Sets the Target Function Restiction
    /// @dev    This is restricted to the module admin.
    /// @dev    This is restricted to existing modules.
    /// @param  target_ The target address.
    /// @param  selectors_ The function selectors.
    /// @param  roleId_ The role id.
    function setTargetFunctionRoleAsModuleAdmin(
        address target_,
        bytes4[] calldata selectors_,
        uint64 roleId_
    ) external;
}
