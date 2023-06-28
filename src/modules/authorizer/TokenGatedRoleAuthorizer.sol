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

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The function is only callable by an active Module.
    error Module__TokenGatedRoleAuthorizer__RoleNotTokenGated();

    /// @notice The function is only callable if the Module is self-managing its roles.
    error Module__TokenGatedRoleAuthorizer__RoleAlreadyInitialized();

    /// @notice There always needs to be at least one owner.
    error Module__TokenGatedRoleAuthorizer__OwnerRoleCannotBeEmpty();



    //--------------------------------------------------------------------------
    // Storage

    mapping(bytes32 => bool) isTokenGated;
    mapping(bytes32 => uint) thresholdMap;

    /// @dev Sets up a token-gated empty role.
    function makeRoleTokenGated(uint8 role) public onlyModule(_msgSender()) onlySelfManaged {
        bytes32 roleId = generateRoleId(_msgSender(), role);

        if (getRoleMemberCount(roleId) != 0) {
            revert Module__TokenGatedRoleAuthorizer__RoleAlreadyInitialized();
        }
        isTokenGated[roleId] = true;
    }

    /// @dev Admin access for rescue purposes.
    function setTokenGated(bytes32 role, bool to) public
        onlyRole(getRoleAdmin(role))
    {
        isTokenGated[role] = to;
    }

    /// @dev This function does not validate the threshold. It is technically possible to set a threshold above the total supply of the token.
    function setThreshold(
        address module,
        uint8 role,
        address token,
        uint threshold
    ) public onlyModule(module) {
        //TODO: Is there a way to move this to modifiers?

        //generate Role Id
        bytes32 roleId = generateRoleId(module, role);

        //check if ID is token gated
        if (!isTokenGated[roleId]) {
            revert Module__TokenGatedRoleAuthorizer__RoleNotTokenGated();
        }

        //check that the caller is either the module itself or the role admin
        if (
            !(module == _msgSender())
                && !hasRole(getRoleAdmin(roleId), _msgSender())
        ) {
            revert Module__CallerNotAuthorized();
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
