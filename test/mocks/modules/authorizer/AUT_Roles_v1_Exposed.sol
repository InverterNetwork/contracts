// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;
// Internal Dependencies

import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";

contract AUT_Roles_v1_Exposed is AUT_Roles_v1 {
    //==========================================================================
    // State Access Functions

    function changeRoleIdCounter(uint newRoleIdCounterValue_) external {
        _roleIdCounter = newRoleIdCounterValue_;
    }

    function addAccessPermission_unrestricted(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) external {
        _permissions[target_][selector_].push(roleId_);
    }

    //==========================================================================
    // Modifiers

    function idNotDefaultAdminModifier_exposed(bytes32 roleId_)
        public
        idNotDefaultAdmin(roleId_)
    {}

    function idExistsModifier_exposed(bytes32 roleId_)
        public
        idExists(roleId_)
    {}

    //==========================================================================
    // Helper Functions
}
