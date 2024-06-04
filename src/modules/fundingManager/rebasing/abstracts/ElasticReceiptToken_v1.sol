// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

// Internal Dependencies
import {ElasticReceiptTokenBase_v1} from
    "@fm/rebasing/abstracts/ElasticReceiptTokenBase_v1.sol";

/**
 * @title   Elastic Receipt Token
 *
 * @notice  Provides a token contract with elastic supply properties
 *
 * @dev     Inherits from {ElasticReceiptTokenBase_v1}. It utilizes a system where all bits
 *          are initially assigned to the zero address to manage the elastic supply during mint
 *          and burn.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
abstract contract ElasticReceiptToken_v1 is ElasticReceiptTokenBase_v1 {
    //--------------------------------------------------------------------------
    // Constructor

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
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
