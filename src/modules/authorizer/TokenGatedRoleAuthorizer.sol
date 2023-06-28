// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;
// External Libraries

import {RoleAuthorizer} from "./RoleAuthorizer.sol";

interface TokenInterface {
    function balanceOf(address _owner) external view returns (uint balance);
}

contract TokenGatedRoleAuthorizer is RoleAuthorizer {
    /*
    * This Module expands on the RoleAuthorizer by adding the possibility to set a role as "Token-Gated"
    * Instead of whitelisting a user address, the whitelisted addresses will correspond to a token address, and on authotrization the contract will check on ownership
    * of one of the specifed tokens.
    */

    mapping(bytes32 => bool) isTokenGated;
    mapping(bytes32 => uint) thresholdMap;

    modifier onlyEmptyRole(bytes32 role) {
        //Check that the role is empty
        if (getRoleMemberCount(role) != 0) {
            // TODO make real error;
            revert("Role is not empty");
        }
        _;
    }

    function toggleTokenGated(bytes32 role)
        public
        onlyModule
        onlySelfManaged
        onlyEmptyRole(role)
    {
        isTokenGated[role] = !isTokenGated[role];
    }

    /// @dev This function does not validate the threshold. It is technically possible to set a threshold above the total supply of the token.
    function setThreshold(address module, uint8 role, address token, uint threshold)
        public
    {
        //generate Role Id
        bytes32 roleId = generateRoleId(module, role);

        //check if ID is token gated
        if (!isTokenGated[roleId]) {
            // TODO make real error;
            revert("Role is not token-gated");
        }

        //check if Module is active
        if (!proposal().isModule(module)) {
            // TODO make real error;
            revert("Module not active");
        }

        //check that the caller is either the module itself or the role admin
        if (
            !(module == _msgSender())
                && !hasRole(getRoleAdmin(roleId), _msgSender())
        ) {
            // TODO make real error;
            revert("not allowed to set threshold");
        }

        bytes32 thresholdId = keccak256(abi.encodePacked(roleId, token));
        thresholdMap[thresholdId] = threshold;
    }

    function isAuthorized(uint8 role, address who)
        public
        view
        override
        returns (bool)
    {
        //Note: since it uses msgSender to generate ID, this should only be used by modules. Users should call hasRole()
        bytes32 roleId;
        // If the module uses its own roles, check if account has the role.
        // else check if account has role in proposal
        if (selfManagedModules[_msgSender()]) {
            //generate role hash
            roleId = generateRoleId(_msgSender(), role);
            //check if token gated:
            if (isTokenGated[roleId]) {
                // check if it qualifies for  token ownership
                return hasTokenRole(roleId, who);
            } else {
                // regular module role check
                return hasRole(roleId, who);
            }
        } else {
            //check if in global roles
            roleId = generateRoleId(address(proposal()), role);
            return hasRole(roleId, who);
        }
    }

    function hasTokenRole(bytes32 role, address who)
        public
        view
        returns (bool)
    {
        uint numberOfAllowedTokens = getRoleMemberCount(role);

        for (uint i; i < numberOfAllowedTokens; ++i) {
            address tokenAddr = getRoleMember(role, i);
            bytes32 thresholdId = keccak256(abi.encodePacked(role, tokenAddr));
            uint tokenThreshold = thresholdMap[thresholdId];

            //Should work with both ERC20 and ERC721
            try TokenInterface(tokenAddr).balanceOf(who) returns (
                uint tokenBalance
            ) {
                if (tokenBalance >= tokenThreshold) {
                    return true;
                }
            } catch {
                // TODO make real error;
                //revert("Unsupported Token Type.");
                // TODO: maybe just emit an event? BalanceQueryFailed or sth like that. that way the module doens't brick if non token gets whitelisted.
            }
        }

        return false;
    }
}
