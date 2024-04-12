// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;
// External Libraries

import {ITokenGatedRoleAuthorizer} from "./ITokenGatedRoleAuthorizer.sol";
import {
    IAuthorizer,
    RoleAuthorizer,
    AccessControlEnumerableUpgradeable
} from "./RoleAuthorizer.sol";
import {
    AccessControlUpgradeable,
    IAccessControlUpgradeable
} from "@oz-up/access/AccessControlUpgradeable.sol";

interface TokenInterface {
    function balanceOf(address _owner) external view returns (uint balance);
}

contract TokenGatedRoleAuthorizer is
    ITokenGatedRoleAuthorizer,
    RoleAuthorizer
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(RoleAuthorizer)
        returns (bool)
    {
        return interfaceId == type(ITokenGatedRoleAuthorizer).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /*
    * This Module expands on the RoleAuthorizer by adding the possibility to set a role as "Token-Gated"
    * Instead of whitelisting a user address, the whitelisted addresses will correspond to a token address, and on authotrization the contract will check on ownership
    * of one of the specifed tokens.
    */

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

    // Stores if a role is token gated.
    mapping(bytes32 => bool) public isTokenGated;
    // Stores the threshold amount for each token in a role
    mapping(bytes32 => uint) public thresholdMap;

    //--------------------------------------------------------------------------
    // Overloaded and overriden functions

    function hasRole(bytes32 roleId, address account)
        public
        view
        virtual
        override(AccessControlUpgradeable, IAccessControlUpgradeable)
        returns (bool)
    {
        if (isTokenGated[roleId]) {
            return _hasTokenRole(roleId, account);
        } else {
            return super.hasRole(roleId, account);
        }
    }

    /// @notice Grants a role to an address
    /// @param role The role to grant
    /// @param account The address to grant the role to
    /// @dev Overrides {_grantRole} from AccesControl to enforce interface implementation when role is token-gated
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

    /// @inheritdoc ITokenGatedRoleAuthorizer
    function hasTokenRole(bytes32 role, address who)
        external
        view
        onlyTokenGated(role)
        returns (bool)
    {
        return _hasTokenRole(role, who);
    }

    /// @inheritdoc ITokenGatedRoleAuthorizer
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

    /// @inheritdoc ITokenGatedRoleAuthorizer
    function makeRoleTokenGatedFromModule(bytes32 role)
        public
        onlyModule(_msgSender())
        onlyEmptyRole(generateRoleId(_msgSender(), role))
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);

        isTokenGated[roleId] = true;
        emit ChangedTokenGating(roleId, true);
    }

    /// @inheritdoc ITokenGatedRoleAuthorizer
    function grantTokenRoleFromModule(
        bytes32 role,
        address token,
        uint threshold
    ) external onlyModule(_msgSender()) {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _grantRole(roleId, token);
        _setThreshold(roleId, token, threshold);
    }

    /// @inheritdoc ITokenGatedRoleAuthorizer
    function setThresholdFromModule(bytes32 role, address token, uint threshold)
        public
        onlyModule(_msgSender())
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _setThreshold(roleId, token, threshold);
    }

    //--------------------------------------------------------------------------
    // Setters for the Admin

    /// @inheritdoc ITokenGatedRoleAuthorizer
    function setTokenGated(bytes32 role, bool to)
        public
        onlyRole(getRoleAdmin(role))
        onlyEmptyRole(role)
    {
        isTokenGated[role] = to;
        emit ChangedTokenGating(role, to);
    }

    /// @inheritdoc ITokenGatedRoleAuthorizer
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
    /// @param threshold The user will need to have at least this number to qualify for the role.
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

    /// @notice Internal function that checks if an account qualifies for a token-gated role.
    /// @param role The role to be checked.
    /// @param who The account to be checked.
    function _hasTokenRole(bytes32 role, address who)
        internal
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
}
