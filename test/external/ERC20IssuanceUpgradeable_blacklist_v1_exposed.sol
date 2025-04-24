// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {ERC20IssuanceUpgradeable_Blacklist_v1} from
    "@ex/token/ERC20IssuanceUpgradeable_Blacklist_v1.sol";

/**
 * @title   ERC20IssuanceUpgradeable_Blacklist_v1_Exposed
 * @dev     Contract that exposes internal functions of
 *          ERC20IssuanceUpgradeable_Blacklist_v1 for testing purposes
 */
contract ERC20IssuanceUpgradeable_Blacklist_v1_Exposed is
    ERC20IssuanceUpgradeable_Blacklist_v1
{
    /**
     * @dev Exposes the internal _update function for testing
     * @param from_ Address tokens are transferred from
     * @param to_ Address tokens are transferred to
     * @param amount_ Amount of tokens transferred
     */
    function exposed_update(address from_, address to_, uint amount_) public {
        _update(from_, to_, amount_);
    }

    /**
     * @dev Exposes the internal _setBlacklistManager function for testing
     * @param account_ Address to set privileges for
     * @param privileges_ Whether to grant or revoke privileges
     */
    function exposed_setBlacklistManager(address account_, bool privileges_)
        public
    {
        _setBlacklistManager(account_, privileges_);
    }

    function exposed_mint(address to_, uint amount_) public {
        _mint(to_, amount_);
    }

    function exposed_addToBlacklist(address account_) public {
        _addToBlacklist(account_);
    }

    function exposed_removeFromBlacklist(address account_) public {
        _removeFromBlacklist(account_);
    }
}
