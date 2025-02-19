// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {ERC20Issuance_Blacklist_v1} from
    "@ex/token/ERC20Issuance_Blacklist_v1.sol";

/**
 * @title ERC20Issuance_Blacklist_v1_Exposed
 * @dev Contract that exposes internal functions of ERC20Issuance_Blacklist_v1 for testing purposes
 */
contract ERC20Issuance_Blacklist_v1_Exposed is ERC20Issuance_Blacklist_v1 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint initialSupply_,
        address initialAdmin_,
        address initialBlacklistManager_
    )
        ERC20Issuance_Blacklist_v1(
            name_,
            symbol_,
            decimals_,
            initialSupply_,
            initialAdmin_,
            initialBlacklistManager_
        )
    {}

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
}
