// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {ERC20IssuanceUpgradeable_v1} from
    "@ex/token/ERC20IssuanceUpgradeable_v1.sol";
import {IERC20Issuance_Blacklist_v1} from
    "@ex/token/interfaces/IERC20Issuance_Blacklist_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20CappedUpgradeable} from
    "@oz-up/token/ERC20/extensions/ERC20CappedUpgradeable.sol";

/**
 * @title   ERC20 Issuance Token with Blacklist Functionality (Upgradeable)
 *
 * @notice  An upgradeable ERC20 token implementation that extends
 *          ERC20IssuanceUpgradeable_v1 with blacklisting capabilities, allowing
 *          designated managers to restrict specific addresses from token operations.
 *
 * @dev     This contract inherits from:
 *              - IERC20Issuance_Blacklist_v1
 *              - ERC20IssuanceUpgradeable_v1
 *
 *          Key features:
 *              - Individual address blacklisting
 *              - Batch blacklisting operations (multiple addresses at once)
 *              - Role-based access control:
 *                  * Contract owner assigns blacklist managers
 *                  * Only blacklist managers can add/remove addresses from blacklist
 *              - Support for contract upgrades through OpenZeppelin's
 *                upgradeable pattern
 *
 *          Access control structure:
 *              - Owner: Controls who can be a blacklist manager
 *              - Blacklist Manager: Controls which addresses are blacklisted
 *
 * @custom:setup    This contract requires the following MANDATORY setup steps:
 *
 *                  1. Set Minter:
 *                     - Purpose: The contract needs a minter to handle token
 *                                minting and burning operations. Without this
 *                                permission, the workflow cannot mint or burn
 *                                tokens.
 *                     - How:     The owner of the contract must call the
 *                                setMinter function to authorize the Funding
 *                                Manager of the workflow
 *                     - Example: token.setMinter(fundingManagerAddress, true);
 *
 *                  2. Set Blacklist Manager:
 *                     - Purpose: The contract needs a blacklist manager to handle
 *                                blacklisting operations. This role can add or
 *                                remove addresses from the blacklist.
 *                     - How:     The owner of the contract must call the
 *                                setBlacklistManager function to authorize a
 *                                trusted address
 *                     - Example: token.setBlacklistManager(trustedAddress, true);
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
contract ERC20IssuanceUpgradeable_Blacklist_v1 is
    IERC20Issuance_Blacklist_v1,
    ERC20IssuanceUpgradeable_v1
{
    // -------------------------------------------------------------------------
    // Constants

    /// @notice	Maximum number of addresses that can be blacklisted in a batch.
    uint public constant BATCH_LIMIT = 200;

    // -------------------------------------------------------------------------
    // Storage

    /// @notice	Mapping of blacklisted addresses.
    mapping(address account => bool isBlacklisted) private _blacklist;

    /// @notice	Mapping of blacklist manager addresses.
    mapping(address account => bool isManager) private _blacklistManager;

    /// @notice    Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to check if the caller is a blacklist manager.
    modifier onlyBlacklistManager() {
        if (!_isBlacklistManager(_msgSender())) {
            revert ERC20Issuance_Blacklist_NotBlacklistManager();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // Initializer

    /// @notice Initializes the ERC20IssuanceUpgradeable_Blacklist_v1 contract.
    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    /// @param decimals_ The number of decimals of the token.
    /// @param maxSupply_ The maximum supply of the token.
    function __ERC20IssuanceBlacklist_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint maxSupply_
    ) public initializer {
        __ERC20Issuance_init(name_, symbol_, decimals_, maxSupply_);
    }

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc	IERC20Issuance_Blacklist_v1
    function isBlacklisted(address account_)
        public
        view
        virtual
        returns (bool)
    {
        return _blacklist[account_];
    }

    /// @inheritdoc	IERC20Issuance_Blacklist_v1
    function isBlacklistManager(address account_)
        external
        view
        virtual
        returns (bool)
    {
        return _isBlacklistManager(account_);
    }

    // -------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function addToBlacklist(address account_)
        public
        virtual
        onlyBlacklistManager
    {
        _addToBlacklist(account_);
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklist(address account_)
        public
        virtual
        onlyBlacklistManager
    {
        _removeFromBlacklist(account_);
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function addToBlacklistBatched(address[] memory accounts_)
        external
        virtual
        onlyBlacklistManager
    {
        uint totalAccounts = accounts_.length;
        if (totalAccounts > BATCH_LIMIT) {
            revert ERC20Issuance_Blacklist_BatchLimitExceeded(
                totalAccounts, BATCH_LIMIT
            );
        }
        for (uint i; i < totalAccounts; ++i) {
            _addToBlacklist(accounts_[i]);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklistBatched(address[] memory accounts_)
        external
        virtual
        onlyBlacklistManager
    {
        uint totalAccounts = accounts_.length;
        if (totalAccounts > BATCH_LIMIT) {
            revert ERC20Issuance_Blacklist_BatchLimitExceeded(
                totalAccounts, BATCH_LIMIT
            );
        }
        for (uint i; i < totalAccounts; ++i) {
            _removeFromBlacklist(accounts_[i]);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function setBlacklistManager(address manager_, bool allowed_)
        external
        virtual
        onlyOwner
    {
        _setBlacklistManager(manager_, allowed_);
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Internal hook to enforce blacklist restrictions on token
    ///         transfers.
    /// @dev    Overrides ERC20CappedUpgradeable._update to add blacklist checks.
    /// @param  from_ Address tokens are transferred from.
    /// @param  to_ Address tokens are transferred to.
    /// @param  amount_ Number of tokens to transfer.
    /// @inheritdoc ERC20CappedUpgradeable
    function _update(address from_, address to_, uint amount_)
        internal
        virtual
        override(ERC20CappedUpgradeable)
    {
        if (isBlacklisted(from_)) {
            revert ERC20Issuance_Blacklist_BlacklistedAddress(from_);
        }
        if (isBlacklisted(to_)) {
            revert ERC20Issuance_Blacklist_BlacklistedAddress(to_);
        }
        super._update(from_, to_, amount_);
    }

    /// @notice Internal function to set a blacklist manager.
    /// @param  manager_ Address to set as blacklist manager.
    /// @param  allowed_ Whether to grant or revoke the blacklist manager role.
    function _setBlacklistManager(address manager_, bool allowed_)
        internal
        virtual
    {
        if (manager_ == address(0)) {
            revert ERC20Issuance_Blacklist_ZeroAddress();
        }
        _blacklistManager[manager_] = allowed_;
        emit BlacklistManagerUpdated(manager_, allowed_, _msgSender());
    }

    /// @notice Internal function to check if an address is a blacklist manager.
    /// @param  manager_ Address to check.
    /// @return bool True if the address is a blacklist manager, false otherwise.
    function _isBlacklistManager(address manager_)
        internal
        view
        virtual
        returns (bool)
    {
        return _blacklistManager[manager_];
    }

    /// @notice Internal function to add an address to the blacklist.
    /// @dev    This function only updates the blacklist state if the address is
    ///         not already blacklisted to prevent unnecessary state changes.
    /// @param  account_ Address to add to the blacklist.
    function _addToBlacklist(address account_) internal virtual {
        if (account_ == address(0)) {
            revert ERC20Issuance_Blacklist_ZeroAddress();
        }
        if (!isBlacklisted(account_)) {
            _blacklist[account_] = true;
            emit AddedToBlacklist(account_, _msgSender());
        }
    }

    /// @notice Internal function to remove an address from the blacklist.
    /// @dev    This function only updates the blacklist state if the address is
    ///         currently blacklisted to prevent unnecessary state changes.
    /// @param  account_ Address to remove from the blacklist.
    function _removeFromBlacklist(address account_) internal virtual {
        if (isBlacklisted(account_)) {
            _blacklist[account_] = false;
            emit RemovedFromBlacklist(account_, _msgSender());
        }
    }
}
