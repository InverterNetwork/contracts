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
    error Module__TokenGatedRoleAuthorizer__RoleNotEmpty();

    /// @notice The token doesn't support balance query.
    error Module__TokenGatedRoleAuthorizer__InvalidToken(address token);

    /// @notice The given threshold is invalid
    error Module__TokenGatedRoleAuthorizer__InvalidThreshold(uint threshold);

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the token-gating of a role changes.
    /// @param role The role that was modified.
    /// @param newValue The new value of the role.
    event ChangedTokenGating(bytes32 role, bool newValue);

    /// @notice Event emitted when the threshold of a token-gated role changes.
    /// @param role The role that was modified.
    /// @param token The token for which the threshold was modified.
    /// @param newValue The new value of the threshold.
    event ChangedTokenThreshold(bytes32 role, address token, uint newValue);

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyEmptyRole(bytes32 roleId) {
        //Check that the role is empty
        if (getRoleMemberCount(roleId) != 0) {
            revert Module__TokenGatedRoleAuthorizer__RoleNotEmpty();
        }

        _;
    }

    modifier onlyTokenGated(bytes32 roleId) {
        if (!isTokenGated[roleId]) {
            revert Module__TokenGatedRoleAuthorizer__RoleNotTokenGated();
        }
        _;
    }

    modifier validThreshold(uint threshold) {
        // Since base ERC721 does not have a total/max supply, we can only enforce that the value should be non-zero
        if (threshold == 0) {
            revert Module__TokenGatedRoleAuthorizer__InvalidThreshold(threshold);
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    mapping(bytes32 => bool) public isTokenGated;
    mapping(bytes32 => uint) public thresholdMap;

    //--------------------------------------------------------------------------
    // Overloaded and overriden functions

    /// @inheritdoc RoleAuthorizer
    /// @dev We add a check to call a different function if the role is token-gated.
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

    /**
     * @dev Overloads {_grantRole} to enforce interface implementation when role is token-gated
     */
    function _grantRole(bytes32 role, address account)
        internal
        virtual
        override
    {
        if (isTokenGated[role]) {
            try TokenInterface(account).balanceOf(address(this)) {}
            catch {
                revert Module__TokenGatedRoleAuthorizer__InvalidToken(account);
            }
        }

        super._grantRole(role, account);
    }

    //--------------------------------------------------------------------------
    // View functions

    /// @notice Checks if an account qualifies for a token-gated role.
    /// @param role The role to be checked.
    /// @param who The account to be checked.
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
                // If the call fails, we continue to the next token.
                // Emitting an event here would make this function (and the functions calling it) non-view.
                // note we already enforce Interface implementation when granting the role.
            }
        }

        return false;
    }

    function getThresholdValue(bytes32 roleId, address token)
        public
        view
        returns (uint)
    {
        bytes32 thresholdId = keccak256(abi.encodePacked(roleId, token));
        return thresholdMap[thresholdId];
    }

    //--------------------------------------------------------------------------
    // State-altering functions

    /// @notice Sets up a token-gated empty role.
    /// @param role The role to be made token-gated
    /// @dev This function is only callable by an active Module for itself. Admin should use setTokenGated().
    function makeRoleTokenGatedFromModule(uint8 role)
        public
        onlyModule(_msgSender())
        onlySelfManaged
        onlyEmptyRole(generateRoleId(_msgSender(), role))
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);

        isTokenGated[roleId] = true;
        emit ChangedTokenGating(roleId, true);
    }

    /// @notice One-step setup for Modules to create a token-gated role and set its threshold.
    /// @param role The role to be made token-gated
    /// @param token The token for which the threshold will be set.
    /// @param threshold The minimum balance of the token required to qualify for the role.
    function grantTokenRoleFromModule(uint8 role, address token, uint threshold)
        external
        onlyModule(_msgSender())
        onlySelfManaged
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _grantRole(roleId, token);
        _setThreshold(roleId, token, threshold);
    }

    //--------------------------------------------------------------------------
    // Setters for the Admin

    /// @notice Sets if a role is token-gated or not.
    /// @param role The ID of the role to be modified
    /// @param to The new value to be set.
    /// @dev Admin access for rescue purposes. If the role has active members, they need to be reovked first.
    function setTokenGated(bytes32 role, bool to)
        public
        onlyRole(getRoleAdmin(role))
        onlyEmptyRole(role)
    {
        isTokenGated[role] = to;
        emit ChangedTokenGating(role, to);
    }

    //change to public func for admin
    function setThreshold(bytes32 roleId, address token, uint threshold)
        public
        onlyRole(getRoleAdmin(roleId))
    {
        _setThreshold(roleId, token, threshold);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the minimum threshold for a token-gated role.
    /// @param roleId  The ID of the role to be modified
    /// @param token The token for which to the threshold.
    /// @param threshold The user will need to have MORE THAN this number to qualify for the role.
    /// @dev This function does not validate the threshold. It is technically possible to set a threshold above the total supply of the token.
    function _setThreshold(bytes32 roleId, address token, uint threshold)
        internal
        onlyTokenGated(roleId)
        validThreshold(threshold)
    {
        bytes32 thresholdId = keccak256(abi.encodePacked(roleId, token));
        thresholdMap[thresholdId] = threshold;
        emit ChangedTokenThreshold(roleId, token, threshold);
    }
}
