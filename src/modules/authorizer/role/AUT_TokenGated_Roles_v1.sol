// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IAUT_TokenGated_Roles_v1} from
    "@aut/role/interfaces/IAUT_TokenGated_Roles_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

// Internal Dependencies
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";

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
    function balanceOf(address _owner) external view returns (uint balance);
}

/**
 * @title   Inverter Token-Gated Role Authorizer
 *
 * @notice  Extends the Inverter's role-based access control to include token gating,
 *          enabling roles to be conditionally assigned based on token ownership.
 *          This mechanism allows for dynamic permissioning tied to specific token
 *          holdings.
 *
 * @dev     Inherits functionality from:
 *          - {IAUT_TokenGated_Roles_v1}: Implementation interface.
 *          - {AUT_Roles_v1}: Inverter's role-based access control.
 *
 *          Key feeatures:
 *              - Token-based access checks before role assignment.
 *              - Supports both {ERC20} and {ERC721} tokens for role eligibility.
 *
 * @custom:guide
 *          The following guide explains in detail how to use the key features
 *          of this module:
 *
 *              - TOKEN BASED ACCESS CONTROL:
 *                  - Token Gated Role:
 *                    With this contract it is possible to extend the base
 *                    functionality of the {AUT_Roles_v1} contract to make a
 *                    role token gated. A token gated role behaves in all
 *                    respects like a regular role, but handles the membership
 *                    of that role differently. A member of a token gated role
 *                    is only allowed to access the role functionalities if
 *                    they hold a certain amount of a token.
 *                    The implementation of this contract uses a few tricks to
 *                    achieve this. Without going into too much detail, this
 *                    is the main part that is needed to understand the basic
 *                    mechanism:
 *                    In the contract the token gating is done by instead of
 *                    saving the members of the role directly in the members
 *                    property of the role, the contract saves the token
 *                    address that will gate the role in the property. That way
 *                    the token address can be looked up and the threshold
 *                    amount compared to the token balance of incoming users.
 *                    Example: We want to adapt a role so that it can only be
 *                    accessed by users that hold a certain amount of token A.
 *                    So we make the role token gated and set a threshold of
 *                    how many tokens a address needs to hold to be able to
 *                    access the role. The moment we use the grantRole function
 *                    to add the address of token A to the members property of
 *                    the role, the role will only be accessible by users that
 *                    hold the threshold amount of token A.
 *
 *                  - Making a role token gated:
 *                    Making a role token gated is done by calling the
 *                    `setTokenGated` function. This function takes the following
 *                    parameters:
 *                    - The role id of the role that we change the token gated
 *                      status of.
 *                    - The boolean that indicates if the role should be token
 *                      gated or not.
 *                    This function can only be called by a permissioned address
 *                    (See permissioned section in the {AUT_Roles_v1} contract).
 *                    Also the role can not contain any members, when it is
 *                    switched to and from token gated.
 *                    Example: Making the role "Whitelisted" token gated would
 *                    look like this:
 *                    authorizer.setTokenGated(whitelistedRoleId, true);
 *
 *                  - Setting the token threshold:
 *                    Setting the token threshold needed to pass the token gate
 *                    is done by calling the setTokenThreshold function. This
 *                    function takes the following parameters:
 *                    - The role id of the role to set the threshold for.
 *                    - The address of the token to set the threshold for.
 *                    - The threshold value to set.
 *                    This function can only be called by a permissioned address
 *                    (See permissioned section in the {AUT_Roles_v1} contract).
 *                    This function can be called anytime, even if the role is
 *                    not token gated yet.
 *                    Example: Setting the threshold for the token "USDC" to
 *                    100 would look like this:
 *                    authorizer.setTokenThreshold(
 *                      whitelistedRoleId, USDC, 100);
 *
 *                  - Adding a token to the token gate:
 *                    Adding a token to the token gate is done by calling the
 *                    grantRole function. This function takes the following
 *                    parameters:
 *                    - The role id of the role to grant.
 *                    - The address of the token to grant the role to.
 *                    The grantRole function can only be called by according
 *                    admin of the role. In addition, the given address needs
 *                    to be a contract, already have a threshold set and
 *                    contain the balanceOf function.
 *                    If the role is not token gated then grantRole will
 *                    behave like the regular grantRole function.
 *                    Example: Adding a token gate to the token gated role
 *                    "Whitelisted" would look like this:
 *                    authorizer.grantRole(whitelistedRoleId, address(USDC));
 *
 *                  - Removing a token from the token gate:
 *                    Removing a token from the token gate is done by calling
 *                    the revokeRole function. This function behaves like the
 *                    regular revokeRole function, except that it sets the
 *                    threshold for the role and token combination to 0 as
 *                    well.
 *                    Example: Removing the token from the role "Whitelisted"
 *                    would look like this:
 *                    authorizer.revokeRole(whitelistedRoleId, address(USDC));
 *
 *                  - Reversing a token gate:
 *                    In case the token gated status of a role needs to be
 *                    reverted, the setTokenGated function can be used. The
 *                    same restrictions as for the setTokenGated function apply
 *                    here as well (see above).
 *                    Example: Reversing the token gated status of the role
 *                    "Whitelisted" would look like this:
 *                    authorizer.setTokenGated(whitelistedRoleId, false);
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
contract AUT_TokenGated_Roles_v1 is IAUT_TokenGated_Roles_v1, AUT_Roles_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(AUT_Roles_v1)
        returns (bool)
    {
        return interfaceId_ == type(IAUT_TokenGated_Roles_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    /*
    * This Module expands on the AUT_Roles_v1 by adding the possibility to set a role as "Token-Gated"
    * Instead of whitelisting a user address, the whitelisted addresses will correspond to a token address, and on
    * authorization the contract will check on ownership of one of the specifed tokens.
    */

    // ========================================================================
    // Modifiers

    /// @notice Modifier to guarantee function is only callable when the role is empty.
    /// @param  roleId_ The ID of the role to be checked.
    modifier onlyEmptyRole(bytes32 roleId_) {
        // Check that the role is empty
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

    /// @notice Modifier to guarantee function is only callable when the role is token-gated.
    /// @param  roleId_ The ID of the role to be checked.
    modifier onlyTokenGated(bytes32 roleId_) {
        if (!_isTokenGated[roleId_]) {
            revert Module__AUT_TokenGated_Roles__RoleNotTokenGated();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable when the threshold is valid.
    /// @param  threshold The threshold to be checked.
    modifier validThreshold(uint threshold) {
        // Since base ERC721 does not have a total/max supply, we can only enforce that the value should be non-zero
        if (threshold == 0) {
            revert Module__AUT_TokenGated_Roles__InvalidThreshold(threshold);
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

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function isTokenGated(bytes32 roleId_)
        external
        view
        returns (bool isTokenGated_)
    {
        return _isTokenGated[roleId_];
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function hasTokenRole(bytes32 roleId_, address who_)
        external
        view
        onlyTokenGated(roleId_)
        returns (bool hasRole_)
    {
        return _hasTokenRole(roleId_, who_);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v1
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

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function setTokenGated(bytes32 roleId_, bool to)
        public
        permissioned
        idExists(roleId_)
        onlyEmptyRole(roleId_)
        notPublicRole(roleId_)
    {
        _isTokenGated[roleId_] = to;
        emit ChangedTokenGating(roleId_, to);
    }

    /// @inheritdoc IAUT_TokenGated_Roles_v1
    function setThreshold(bytes32 roleId_, address token, uint threshold)
        public
        permissioned
        idExists(roleId_)
    {
        _setThreshold(roleId_, token, threshold);
    }

    //--------------------------------------------------------------------------
    // Overloaded and overridden functions

    /// @inheritdoc IAccessControl
    /// @notice In case the role is token gated, it will check if {who_} holds a balance
    ///         above the threshold for at least one of the required tokens.
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
    /// @dev	Overrides {_grantRole} from {AUT_ROLES_v1} to enforce interface implementation and threshold existence
    ///         when role is token-gated.
    /// @dev	Please note: current check for validating a valid token is not conclusive and could be
    ///         circumvented through a `callback()` function.
    function _grantRole(bytes32 roleId_, address who_)
        internal
        virtual
        override
        returns (bool success_)
    {
        if (_isTokenGated[roleId_]) {
            // Check that address has code attached
            uint32 size;
            assembly {
                size := extcodesize(who_)
            }
            if (size == 0) {
                revert Module__AUT_TokenGated_Roles__InvalidToken(who_);
            }

            // Make sure that a threshold has been set before granting the role
            if (getThresholdValue(roleId_, who_) == 0) {
                revert Module__AUT_TokenGated_Roles__TokenRoleMustHaveThreshold(
                    roleId_, who_
                );
            }

            // Execute a balanceOf call to the address
            (bool success, bytes memory data) = who_.call(
                abi.encodeWithSelector(
                    TokenInterface.balanceOf.selector, address(this)
                )
            );
            // If the call was either unsuccessful or the return data is not
            // 32 bytes long (i.e. not a uint256), it's deemed invalid
            if (!success || data.length != 32) {
                revert Module__AUT_TokenGated_Roles__InvalidToken(who_);
            }
        }

        return super._grantRole(roleId_, who_);
    }

    /// @param  roleId_ The id number of the role.
    /// @param  who_ The user we want to check on.
    /// @return success_ Returns if revoke has been succesful.
    /// @dev	Overrides {_revokeRole} to clean up threshold data on revoking.
    function _revokeRole(bytes32 roleId_, address who_)
        internal
        virtual
        override
        returns (bool success_)
    {
        if (_isTokenGated[roleId_]) {
            // Set the threshold to 0 before revoking the role from the token
            bytes32 thresholdId = keccak256(abi.encodePacked(roleId_, who_));
            _thresholdMap[thresholdId] = 0;
            emit ChangedTokenThreshold(roleId_, who_, 0);
        }
        return super._revokeRole(roleId_, who_);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the minimum threshold for a token-gated role.
    /// @param  roleId_  The ID of the role to be modified.
    /// @param  token_ The token for which to the threshold.
    /// @param  threshold_ The user will need to have at least this number to qualify for the role.
    /// @dev	This function does not validate the threshold. It is technically possible to set a threshold above the
    ///         total supply of the token.
    function _setThreshold(bytes32 roleId_, address token_, uint threshold_)
        internal
        onlyTokenGated(roleId_)
        validThreshold(threshold_)
    {
        bytes32 thresholdId = keccak256(abi.encodePacked(roleId_, token_));
        _thresholdMap[thresholdId] = threshold_;
        emit ChangedTokenThreshold(roleId_, token_, threshold_);
    }

    /// @notice Internal function that checks if an account qualifies for a token-gated role.
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

            // Should work with both ERC20 and ERC721
            try TokenInterface(tokenAddr).balanceOf(who_) returns (
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
