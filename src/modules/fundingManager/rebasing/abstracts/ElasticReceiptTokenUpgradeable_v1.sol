// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

// Internal Dependencies
import {ElasticReceiptTokenBase_v1} from
    "@fm/rebasing/abstracts/ElasticReceiptTokenBase_v1.sol";

/**
 * @title   Elastic Receipt Token Upgradeable
 *
 * @notice  Provides an upgradeable token contract with elastic supply properties
 *
 * @dev     Inherits from {ElasticReceiptTokenBase_v1}. Supports reinitialization to set metadata and
 *          initial states as long as no tokens have been minted yet. It utilizes a system where all bits
 *          are initially assigned to the zero address to manage the elastic supply during mint and burn.
 *
 * @author  Inverter Network
 */
abstract contract ElasticReceiptTokenUpgradeable_v1 is
    ElasticReceiptTokenBase_v1
{
    // Storage gap for future upgrades
    uint[50] private __gap;

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ElasticReceiptTokenBase_v1)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Initialization

    /// @dev Initializes the contract.
    /// @dev Reinitialization possible as long as no tokens minted.
    function __ElasticReceiptToken_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal {
        require(_totalTokenSupply == 0);

        // Set IERC20Metadata.
        name = name_;
        symbol = symbol_;
        decimals = decimals_;

        // Total supply of bits are 'pre-mined' to zero address.
        //
        // During mint, bits are transferred from the zero address and
        // during burn, bits are transferred to the zero address.
        _accountBits[address(0)] = TOTAL_BITS;
    }
}
