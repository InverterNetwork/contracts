// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IAUT_TokenGated_Roles_v2} from
    "@aut/role/interfaces/IAUT_TokenGated_Roles_v2.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";

// Internal Dependencies
import {AUT_Roles_v2} from "@aut/role/AUT_Roles_v2.sol";

// External Interfaces
import {IAccessControl} from "@oz/access/IAccessControl.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import {AccessControlUpgradeable} from
    "@oz-up/access/AccessControlUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@oz-up/access/extensions/AccessControlEnumerableUpgradeable.sol";

/**
 * @title   Token Interface
 *
 * @notice  This Interface is an abstraction of token based contracts that is
 *          referenced in the Token-Gated Role Authorizer.
 *
 * @dev     It only contains the balanceOf function, which should be
 *          implemented by any of the following token contracts and their
 *          derivatives:
 *          - ERC20
 *          - ERC721
 *          This interface is used to ensure that the token-gated role
 *          authorizer can be used with any token contract that implements
 *          the balanceOf function.
 *
 * @author  Inverter Network
 */
interface TokenInterface {
    /// @notice Returns the balance of the given address.
    /// @param  owner_ The address to check the balance of.
    /// @return balance_ The balance of the given address.
    function balanceOf(address owner_) external view returns (uint balance_);
}

/**
 * @title   Inverter Token-Gated Role Authorizer
 *
 * @notice  Extends the Inverter's role-based access control to include token
 *          gating, enabling roles to be conditionally assigned based on token
 *          ownership. This mechanism allows for dynamic permissioning tied to
 *          specific token holdings.
 *
 * @dev     Inherits functionality from:
 *          - {IAUT_TokenGated_Roles_v2}: Implementation interface.
 *          - {AUT_Roles_v2}: Inverter's role-based access control.
 *
 *          Key features:
 *              - Token-based access checks before role assignment.
 *              - Supports both {ERC20} and {ERC721} tokens.
 *
 * @custom:documentation See https://github.com/InverterNetwork/contracts/tree/dev/docs/src/modules/authorizer/role/AUT_TokenGated_Roles_v2.md
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
contract AUT_TokenGated_Roles_v2 is IAUT_TokenGated_Roles_v2, AUT_Roles_v2 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(AUT_Roles_v2)
        returns (bool isInterfaceId_)
    {
        return interfaceId_ == type(IAUT_TokenGated_Roles_v2).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    /*
    * This Module expands on the AUT_Roles_v2 by adding the possibility to set
    * a role as "Token-Gated". Instead of whitelisting a user address, the
    * whitelisted addresses will correspond to a token address, and on 
    * authorization the contract will check on ownership of one of the specifed
    * tokens.
    */

    // ========================================================================
    // Modifiers

    /// @notice Modifier to guarantee function is only callable when the role is
    ///         empty.
    /// @param  roleId_ The ID of the role to be checked.
    modifier onlyEmptyRole(bytes32 roleId_) {
        // Check that the role is empty.
        if (getRoleMemberCount(roleId_) != 0) {
            revert Module__AUT_TokenGated_Roles__RoleNotEmpty();
        }

        _;
    }

    /// @notice Modifier to guarantee that the role is not the public role.
    /// @param  roleId_ The ID of the role to be checked.
    modifier notPublicRole(bytes32 roleId_) {
        if (PUBLIC_ROLE == roleId_) {
            revert Module__AUT_TokenGated_Roles__RoleIsPublic();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable when the role
    ///         is token-gated.
    /// @param  roleId_ The ID of the role to be checked.
    modifier onlyTokenGated(bytes32 roleId_) {
        if (!_isTokenGated[roleId_]) {
            revert Module__AUT_TokenGated_Roles__RoleNotTokenGated();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable when the
    ///         threshold is valid.
    /// @param  threshold_ The threshold to be checked.
    modifier validThreshold(uint threshold_) {
        // Since base ERC721 does not have a total/max supply, we can only
        // enforce that the value should be non-zero.
        if (threshold_ == 0) {
            revert Module__AUT_TokenGated_Roles__InvalidThreshold(threshold_);
        }
        _;
    }

    // ========================================================================
    // Storage

    /// @dev	Stores if a role is token gated.
    mapping(bytes32 => bool) internal _isTokenGated;
    /// @dev	Stores the threshold amount for each token in a role.
    mapping(bytes32 => uint) internal _thresholdMap;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    // ========================================================================
    // Public Getter Functions

    /// @inheritdoc IAUT_TokenGated_Roles_v2
    function isTokenGated(bytes32 roleId_)
        external
        view
        returns (bool isTokenGated_)
    {
        return _isTokenGated[roleId_];
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v2
    function hasTokenRole(bytes32 roleId_, address who_)
        external
        view
        onlyTokenGated(roleId_)
        returns (bool hasRole_)
    {
        return _hasTokenRole(roleId_, who_);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v2
    function getThresholdValue(bytes32 roleId_, address token_)
        public
        view
        returns (uint threshold_)
    {
        bytes32 thresholdId = keccak256(abi.encodePacked(roleId_, token_));
        return _thresholdMap[thresholdId];
    }

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - TokenGated Settings

    /// @inheritdoc IAUT_TokenGated_Roles_v2
    function setTokenGated(bytes32 roleId_, bool to_)
        public
        permissioned
        idExists(roleId_)
        onlyEmptyRole(roleId_)
        notPublicRole(roleId_)
    {
        _isTokenGated[roleId_] = to_;
        emit ChangedTokenGating(roleId_, to_);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v2
    function setThreshold(bytes32 roleId_, address token_, uint threshold_)
        public
        permissioned
        idExists(roleId_)
    {
        _setThreshold(roleId_, token_, threshold_);
    }

    //--------------------------------------------------------------------------
    // Overloaded and overridden functions

    /// @inheritdoc IAccessControl
    /// @notice In case the role is token gated, it will check if {who_} holds a
    ///         balance above the threshold for at least one of the required
    ///tokens.
    /// @param  roleId_ The id number of the role.
    /// @param  who_ The user we want to check on.
    /// @return hasRole_ Returns if the account has the role.
    function hasRole(bytes32 roleId_, address who_)
        public
        view
        virtual
        override(AccessControlUpgradeable, IAccessControl)
        returns (bool hasRole_)
    {
        if (_isTokenGated[roleId_]) {
            return _hasTokenRole(roleId_, who_);
        } else {
            return super.hasRole(roleId_, who_);
        }
    }

    /// @notice Grants a role to an address.
    /// @param  roleId_ The role to grant.
    /// @param  who_ The address to grant the role to.
    /// @return success_ Returns true if the role has been granted succesfully.
    /// @dev	Overrides {_grantRole} from {AUT_Roles_v2} to enforce interface
    ///         implementation and threshold existence when role is token-gated.
    /// @dev	Please note: current check for validating a valid token is not
    ///         conclusive and could be circumvented through a `callback()`
    ///         function.
    function _grantRole(bytes32 roleId_, address who_)
        internal
        virtual
        override
        returns (bool success_)
    {
        if (_isTokenGated[roleId_]) {
            // Check that address has code attached.
            uint32 size;
            assembly {
                size := extcodesize(who_)
            }
            if (size == 0) {
                revert Module__AUT_TokenGated_Roles__InvalidToken(who_);
            }

            // Make sure that a threshold has been set before granting the role.
            if (getThresholdValue(roleId_, who_) == 0) {
                revert Module__AUT_TokenGated_Roles__TokenRoleMustHaveThreshold(
                    roleId_, who_
                );
            }

            // Execute a balanceOf call to the address.
            (bool success, bytes memory data) = who_.call(
                abi.encodeWithSelector(
                    TokenInterface.balanceOf.selector, address(this)
                )
            );
            // If the call was either unsuccessful or the return data is not
            // 32 bytes long (i.e. not a uint256), it's deemed invalid.
            if (!success || data.length != 32) {
                revert Module__AUT_TokenGated_Roles__InvalidToken(who_);
            }
        }

        return super._grantRole(roleId_, who_);
    }

    /// @notice Revokes a role from an address.
    /// @dev	Overrides {_revokeRole} to clean up threshold data on revoking.
    /// @param  roleId_ The id number of the role.
    /// @param  who_ The user we want to check on.
    /// @return success_ Returns if revoke has been succesful.

    function _revokeRole(bytes32 roleId_, address who_)
        internal
        virtual
        override
        returns (bool success_)
    {
        if (_isTokenGated[roleId_]) {
            // Set the threshold to 0 before revoking the role from the token.
            bytes32 thresholdId = keccak256(abi.encodePacked(roleId_, who_));
            _thresholdMap[thresholdId] = 0;
            emit ChangedTokenThreshold(roleId_, who_, 0);
        }
        return super._revokeRole(roleId_, who_);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the minimum threshold for a token-gated role.
    /// @dev	This function does not validate the threshold. It is
    ///         technically possible to set a threshold above the total supply
    ///         of the token.
    /// @param  roleId_  The ID of the role to be modified.
    /// @param  token_ The token for which to the threshold.
    /// @param  threshold_ The user will need to have at least this number to
    ///         qualify for the role.

    function _setThreshold(bytes32 roleId_, address token_, uint threshold_)
        internal
        onlyTokenGated(roleId_)
        validThreshold(threshold_)
    {
        bytes32 thresholdId = keccak256(abi.encodePacked(roleId_, token_));
        _thresholdMap[thresholdId] = threshold_;
        emit ChangedTokenThreshold(roleId_, token_, threshold_);
    }

    /// @notice Internal function that checks if an account qualifies for a
    ///         token-gated role.
    /// @param  roleId_ The id of the role to be checked.
    /// @param  who_ The account to be checked.
    /// @return hasRokenRole_ Returns if the account has the role.
    function _hasTokenRole(bytes32 roleId_, address who_)
        internal
        view
        returns (bool hasRokenRole_)
    {
        uint numberOfAllowedTokens = getRoleMemberCount(roleId_);

        address tokenAddr;
        bytes32 thresholdId;
        uint tokenThreshold;
        for (uint i; i < numberOfAllowedTokens; ++i) {
            tokenAddr = getRoleMember(roleId_, i);
            thresholdId = keccak256(abi.encodePacked(roleId_, tokenAddr));
            tokenThreshold = _thresholdMap[thresholdId];

            // Should work with both ERC20 and ERC721.
            try TokenInterface(tokenAddr).balanceOf(who_) returns (
                uint tokenBalance
            ) {
                if (tokenBalance >= tokenThreshold) {
                    return true;
                }
            } catch {
                // If the call fails, we continue to the next token.
                // Emitting an event here would make this function
                // (and the functions calling it) non-view.
                // note we already enforce Interface implementation when
                // granting the role.
            }
        }

        return false;
    }
}
