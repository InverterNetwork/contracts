// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {IERC20Issuance_Blacklist_v1} from
    "@ex/token/interfaces/IERC20Issuance_Blacklist_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@oz/token/ERC20/extensions/ERC20Capped.sol";

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
contract ERC20Issuance_Blacklist_v1 is
    IERC20Issuance_Blacklist_v1,
    ERC20Issuance_v1
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
    // Constructor

    /// @notice	Constructor for ERC20Issuance_Blacklist_v1.
    /// @param	name_ Token name.
    /// @param	symbol_ Token symbol.
    /// @param	decimals_ Token decimals.
    /// @param	maxSupply_ Max token supply.
    /// @param	initialAdmin_ Initial admin address.
    /// @param	initialBlacklistManager_ Initial blacklist manager (typically an
    ///         EOA).
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint maxSupply_,
        address initialAdmin_,
        address initialBlacklistManager_
    ) ERC20Issuance_v1(name_, symbol_, decimals_, maxSupply_, initialAdmin_) {
        _setBlacklistManager(initialBlacklistManager_, true);
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
        if (account_ == address(0)) {
            revert ERC20Issuance_Blacklist_ZeroAddress();
        }
        if (!isBlacklisted(account_)) {
            _blacklist[account_] = true;
            emit AddedToBlacklist(account_, _msgSender());
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklist(address account_)
        public
        virtual
        onlyBlacklistManager
    {
        if (isBlacklisted(account_)) {
            _blacklist[account_] = false;
            emit RemovedFromBlacklist(account_, _msgSender());
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function addToBlacklistBatched(address[] memory accounts_)
        external
        virtual
    {
        uint totalAccounts = accounts_.length;
        if (totalAccounts > BATCH_LIMIT) {
            revert ERC20Issuance_Blacklist_BatchLimitExceeded(
                totalAccounts, BATCH_LIMIT
            );
        }
        for (uint i; i < totalAccounts; ++i) {
            addToBlacklist(accounts_[i]);
        }
    }

    /// @inheritdoc IERC20Issuance_Blacklist_v1
    function removeFromBlacklistBatched(address[] memory accounts_)
        external
        virtual
    {
        uint totalAccounts = accounts_.length;
        if (totalAccounts > BATCH_LIMIT) {
            revert ERC20Issuance_Blacklist_BatchLimitExceeded(
                totalAccounts, BATCH_LIMIT
            );
        }
        for (uint i; i < totalAccounts; ++i) {
            removeFromBlacklist(accounts_[i]);
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

    /// @notice Internal hook to enforce blacklist restrictions on token transfers.
    /// @dev    Overrides ERC20Capped._update to add blacklist checks.
    /// @param  from_ Address tokens are transferred from.
    /// @param  to_ Address tokens are transferred to.
    /// @param  amount_ Number of tokens to transfer.
    /// @inheritdoc ERC20Capped
    function _update(address from_, address to_, uint amount_)
        internal
        virtual
        override(ERC20Capped)
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
}
