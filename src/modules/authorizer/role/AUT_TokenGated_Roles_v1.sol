// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IAUT_TokenGated_Roles_v1} from
    "@aut/role/interfaces/IAUT_TokenGated_Roles_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

// Internal Dependencies
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";

// External Interfaces
import {IAccessControl} from "@oz/access/IAccessControl.sol";

// External Dependencies
import {AccessControlUpgradeable} from
    "@oz-up/access/AccessControlUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@oz-up/access/extensions/AccessControlEnumerableUpgradeable.sol";

interface TokenInterface {
    function balanceOf(address _owner) external view returns (uint balance);
}

/**
 * @title   Token-Gated Role Authorizer
 *
 * @notice  Extends the Inverter's role-based access control to include token gating,
 *          enabling roles to be conditionally assigned based on token ownership.
 *          This mechanism allows for dynamic permissioning tied to specific token
 *          holdings.
 *
 * @dev     Builds on {AUT_Roles_v1} by integrating token-based access checks before
 *          role assignment. Utilizes checks on token balances to gate access,
 *          supporting both ERC20 and ERC721 tokens as qualifiers for role eligibility.
 *
 * @author  Inverter Network
 */
contract AUT_TokenGated_Roles_v1 is IAUT_TokenGated_Roles_v1, AUT_Roles_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AUT_Roles_v1)
        returns (bool)
    {
        return interfaceId == type(IAUT_TokenGated_Roles_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /*
    * This Module expands on the AUT_Roles_v1 by adding the possibility to set a role as "Token-Gated"
    * Instead of whitelisting a user address, the whitelisted addresses will correspond to a token address, and on authotrization the contract will check on ownership
    * of one of the specifed tokens.
    */

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyEmptyRole(bytes32 roleId) {
        //Check that the role is empty
        if (getRoleMemberCount(roleId) != 0) {
            revert Module__AUT_TokenGated_Roles__RoleNotEmpty();
        }

        _;
    }

    modifier onlyTokenGated(bytes32 roleId) {
        if (!isTokenGated[roleId]) {
            revert Module__AUT_TokenGated_Roles__RoleNotTokenGated();
        }
        _;
    }

    modifier validThreshold(uint threshold) {
        // Since base ERC721 does not have a total/max supply, we can only enforce that the value should be non-zero
        if (threshold == 0) {
            revert Module__AUT_TokenGated_Roles__InvalidThreshold(threshold);
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    // Stores if a role is token gated.
    mapping(bytes32 => bool) public isTokenGated;
    // Stores the threshold amount for each token in a role
    mapping(bytes32 => uint) public thresholdMap;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Overloaded and overriden functions

    function hasRole(bytes32 roleId, address who)
        public
        view
        virtual
        override(AccessControlUpgradeable, IAccessControl)
        returns (bool)
    {
        if (isTokenGated[roleId]) {
            return _hasTokenRole(roleId, who);
        } else {
            return super.hasRole(roleId, who);
        }
    }

    /// @notice Grants a role to an address
    /// @param role The role to grant
    /// @param who The address to grant the role to
    /// @return bool Returns if the role has been granted succesful
    /// @dev Overrides {_grantRole} from AccessControl to enforce interface implementation and threshold existence when role is token-gated
    /// @dev Please note: current check for validating a valid token is not conclusive and could be
    ///         circumvented through a callback() function
    function _grantRole(bytes32 role, address who)
        internal
        virtual
        override
        returns (bool)
    {
        if (isTokenGated[role]) {
            // Make sure that a threshold has been set before granting the role
            if (getThresholdValue(role, who) == 0) {
                revert Module__AUT_TokenGated_Roles__TokenRoleMustHaveThreshold(
                    role, who
                );
            }
            try TokenInterface(who).balanceOf(address(this)) {}
            catch {
                revert Module__AUT_TokenGated_Roles__InvalidToken(who);
            }
            // Check that address has code attached
            uint32 size;
            assembly {
                size := extcodesize(who)
            }
            if (size == 0) {
                revert Module__AUT_TokenGated_Roles__InvalidToken(who);
            }
        }

        return super._grantRole(role, who);
    }

    /// @param role The id number of the role
    /// @param who The user we want to check on
    /// @return bool Returns if revoke has been succesful
    /// @dev Overrides {_revokeRole} to clean up threshold data on revoking
    function _revokeRole(bytes32 role, address who)
        internal
        virtual
        override
        returns (bool)
    {
        if (isTokenGated[role]) {
            // Set the threshold to 0 before revoking the role from the token
            bytes32 thresholdId = keccak256(abi.encodePacked(role, who));
            thresholdMap[thresholdId] = 0;
            emit ChangedTokenThreshold(role, who, 0);
        }
        return super._revokeRole(role, who);
    }

    //--------------------------------------------------------------------------
    // View functions

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function hasTokenRole(bytes32 role, address who)
        external
        view
        onlyTokenGated(role)
        returns (bool)
    {
        return _hasTokenRole(role, who);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v1
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

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function makeRoleTokenGatedFromModule(bytes32 role)
        public
        onlyModule(_msgSender())
        onlyEmptyRole(generateRoleId(_msgSender(), role))
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);

        isTokenGated[roleId] = true;
        emit ChangedTokenGating(roleId, true);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function grantTokenRoleFromModule(
        bytes32 role,
        address token,
        uint threshold
    ) external onlyModule(_msgSender()) {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _setThreshold(roleId, token, threshold);
        _grantRole(roleId, token);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function setThresholdFromModule(bytes32 role, address token, uint threshold)
        public
        onlyModule(_msgSender())
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _setThreshold(roleId, token, threshold);
    }

    //--------------------------------------------------------------------------
    // Setters for the Admin

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function setTokenGated(bytes32 role, bool to)
        public
        onlyRole(getRoleAdmin(role))
        onlyEmptyRole(role)
    {
        isTokenGated[role] = to;
        emit ChangedTokenGating(role, to);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v1
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
