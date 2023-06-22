// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";

interface IRoleAuthorizer is IAuthorizer {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a module toggles self management
    /// @param who The module.
    /// @param newValue The new value of the self management flag.
    event setRoleSelfManagement(address who, bool newValue);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The function is only callable by an active Module.
    error Module__RoleAuthorizer__OnlyCallableByModule();

    /// @notice The function is only callable if the Module is self-managing its roles.
    error Module__RoleAuthorizer__ModuleNotSelfManaged();

    /// @notice There always needs to be at least one owner.
    error Module__RoleAuthorizer__OwnerRoleCannotBeEmpty();

    function isAuthorized(uint8 role, address who)
        external
        view
        returns (bool);

    function toggleSelfManagement() external;
}
