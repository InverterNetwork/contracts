// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";

/**
 * @title   ERC20 Issuance Token with Blacklist Functionality
 *
 * @notice  An ERC20 token implementation that extends ERC20Issuance_v1 with
 *          blacklisting capabilities. This allows accounts with the blacklist
 *          manager role to restrict specific addresses from participating in
 *          token operations.
 *
 * @dev     This contract inherits from:
 *              - IERC20Issuance_Blacklist_v1.
 *              - ERC20Issuance_v1.
 *          Key features:
 *              - Individual address blacklisting.
 *              - Batch blacklisting operations.
 *              - Owner-controlled manager role assignment.
 *              - Blacklist manager controlled blacklist management.
 *              Blacklist operations are performed by accounts with the
 *              blacklist manager role, while the contract owner controls who
 *              can be a blacklist manager.
 *          All blacklist operations can only be performed by accounts with the
 *          blacklist manager role.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  Zealynx Security
 */
interface IERC20Issuance_Blacklist_v1 is IERC20Issuance_v1 {
    // -------------------------------------------------------------------------
    // Events

    /// @notice Emitted when an address is added to the blacklist.
    /// @param  account_ The address that was blacklisted.
    /// @param  blacklistManager_ The address that added the address to the blacklist.
    event AddedToBlacklist(
        address indexed account_, address indexed blacklistManager_
    );

    /// @notice Emitted when an address is removed from the blacklist.
    /// @param  account_ The address that was removed from blacklist.
    /// @param  blacklistManager_ The address that removed the address from the blacklist.
    event RemovedFromBlacklist(
        address indexed account_, address indexed blacklistManager_
    );

    /// @notice Emitted when a blacklist manager role is granted or revoked.
    /// @param  account_ The address that was granted or revoked the role.
    /// @param  allowed_ Whether the role was granted (true) or revoked (false).
    /// @param  tokenOwner_ The address that owns the token.
    event BlacklistManagerUpdated(
        address indexed account_, bool allowed_, address indexed tokenOwner_
    );

    // -------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when attempting to blacklist the zero address.
    error ERC20Issuance_Blacklist_ZeroAddress();

    /// @notice Thrown when caller does not have blacklist manager role.
    error ERC20Issuance_Blacklist_NotBlacklistManager();

    /// @notice Thrown when attempting to mint tokens to a blacklisted address.
    error ERC20Issuance_Blacklist_BlacklistedAddress(address account_);

    /// @notice Thrown when batch operation exceeds the maximum allowed size.
    error ERC20Issuance_Blacklist_BatchLimitExceeded(
        uint provided_, uint limit_
    );

    // -------------------------------------------------------------------------
    // External Functions

    /// @notice Checks if an address is blacklisted.
    /// @param  account_ The address to check.
    /// @return isBlacklisted_ True if address is blacklisted.
    function isBlacklisted(address account_)
        external
        view
        returns (bool isBlacklisted_);

    /// @notice Checks if an address is a blacklist manager.
    /// @param  account_ The address to check.
    /// @return isBlacklistManager_ True if address is a blacklist manager.
    function isBlacklistManager(address account_)
        external
        view
        returns (bool isBlacklistManager_);

    /// @notice Adds an address to blacklist.
    /// @param  account_ The address to the blacklist.
    /// @dev    May revert with ERC20Issuance_Blacklist_ZeroAddress.
    function addToBlacklist(address account_) external;

    /// @notice Removes an address from the blacklist.
    /// @param  account_ The address to remove.
    /// @dev    May revert with ERC20Issuance_Blacklist_ZeroAddress.
    function removeFromBlacklist(address account_) external;

    /// @notice Adds multiple addresses to the blacklist.
    /// @param  accounts_ Array of addresses to the blacklist.
    /// @dev    May revert with ERC20Issuance_Blacklist_ZeroAddress
    ///         The array size should not exceed the block gas limit. Consider
    ///         using smaller batches (e.g., 100-200 addresses) to ensure
    ///         transaction success.
    function addToBlacklistBatched(address[] calldata accounts_) external;

    /// @notice Removes multiple addresses from the blacklist.
    /// @param  accounts_ Array of addresses to remove.
    /// @dev    May revert with ERC20Issuance_Blacklist_ZeroAddress
    ///         The array size should not exceed the block gas limit. Consider
    ///         using smaller batches (e.g., 100-200 addresses) to ensure
    ///         transaction success.
    function removeFromBlacklistBatched(address[] calldata accounts_)
        external;

    /// @notice Sets or revokes blacklist manager role for an address.
    /// @param  manager_ The address to grant or revoke the role from.
    /// @param  allowed_ Whether to grant (true) or revoke (false) the role.
    /// @dev    May revert with ERC20Issuance_Blacklist_ZeroAddress.
    function setBlacklistManager(address manager_, bool allowed_) external;
}
