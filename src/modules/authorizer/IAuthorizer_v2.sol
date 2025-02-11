// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessManager} from "@oz/access/manager/IAccessManager.sol";
import {IModule_v2} from "src/modules/base/IModule_v2.sol";

interface IAuthorizer_v2 is IAccessManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by a module or the admin.
    error Authorizer_v2__OnlyCallableByModuleOrAdmin();

    /// @notice The given RoleId has not been created yet.
    error Authorizer_v2__RoleIdNotCreated();

    //--------------------------------------------------------------------------
    // Public Getter Functions

    /// @notice Returns the next role id that will be created.
    /// @return currentRoleId_ The next role if that will be created.
    function getCurrentRoleId() external view returns (uint64 currentRoleId_);

    //--------------------------------------------------------------------------
    // Public Mutating Functions

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
}
