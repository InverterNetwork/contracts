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

    function addKey_unrestricted(
        address target_,
        bytes4 selector_,
        bytes32 newRoleIdKey_
    ) external {
        _keys[target_][selector_].push(newRoleIdKey_);
    }

    //==========================================================================
    // Modifiers

    function idNotDefaultAdminModifier_exposed(bytes32 roleId_)
        public
        idNotDefaultAdmin(roleId_)
    {}

    function idExistingModifier_exposed(bytes32 roleId_)
        public
        idExisting(roleId_)
    {}

    //==========================================================================
    // Helper Functions
}
