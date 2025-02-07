// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessManager} from "@oz/access/manager/IAccessManager.sol";

interface IAuthorizer_v2 is IAccessManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by a module or the admin.
    error Authorizer_v2__OnlyCallableByModuleOrAdmin();

    /// @notice The given RoleId has not been created yet.
    error Authorizer_v2__RoleIdNotCreated();

    //--------------------------------------------------------------------------
    // Public getter Functions

    /// @notice Returns the next role id that will be created.
    /// @return currentRoleId_ The next role if that will be created.
    function getCurrentRoleId() external view returns (uint64 currentRoleId_);

    /// @notice Creates a new role and links it to the given name via event.
    /// @dev This is restricted to the admin and to modules that are registered
    ///      in the orchestrator.
    /// @param roleName_ The name of the role to be created.
    /// @return roleId_ The id of the created role.
    function createRole(string calldata roleName_)
        external
        returns (uint64 roleId_);
}
