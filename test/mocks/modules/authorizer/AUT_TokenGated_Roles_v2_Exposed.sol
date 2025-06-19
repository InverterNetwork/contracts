// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;
// Internal Dependencies

import {AUT_TokenGated_Roles_v2} from "@aut/role/AUT_TokenGated_Roles_v2.sol";
import {AccessControlUpgradeable} from
    "@oz-up/access/AccessControlUpgradeable.sol";

contract AUT_TokenGated_Roles_v2_Exposed is AUT_TokenGated_Roles_v2 {
    //==========================================================================
    // Modifier

    function onlyEmptyRoleModifier_exposed(bytes32 roleId_)
        public
        onlyEmptyRole(roleId_)
    {}

    function notPublicRoleModifier_exposed(bytes32 roleId_)
        public
        notPublicRole(roleId_)
    {}

    function onlyTokenGatedModifier_exposed(bytes32 roleId_)
        public
        onlyTokenGated(roleId_)
    {}
    function validThresholdModifier_exposed(uint threshold_)
        public
        validThreshold(threshold_)
    {}

    //==========================================================================
    // Internal Exposed Functions

    function exposed_setThreshold(
        bytes32 roleId_,
        address token_,
        uint threshold_
    ) public {
        _setThreshold(roleId_, token_, threshold_);
    }

    function exposed_hasTokenRole(bytes32 roleId_, address who_)
        public
        view
        returns (bool hasTokenRole_)
    {
        return _hasTokenRole(roleId_, who_);
    }

    function exposed_AccessControlUpgradeable_hasRole(
        bytes32 roleId_,
        address who_
    ) public view returns (bool hasRole_) {
        return AccessControlUpgradeable.hasRole(roleId_, who_);
    }

    //==========================================================================
    // Helper Functions

    function setTokenGated_unrestricted(bytes32 roleId_, bool to_) public {
        _isTokenGated[roleId_] = to_;
    }

    function setThreshold_unrestricted(
        bytes32 roleId_,
        address token_,
        uint threshold_
    ) public {
        bytes32 thresholdId = keccak256(abi.encodePacked(roleId_, token_));
        _thresholdMap[thresholdId] = threshold_;
    }
}
