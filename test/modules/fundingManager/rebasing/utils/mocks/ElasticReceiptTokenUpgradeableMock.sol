// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {
    ElasticReceiptTokenUpgradeable,
    ElasticReceiptTokenBase
} from
    "src/modules/fundingManager/rebasing/abstracts/ElasticReceiptTokenUpgradeable.sol";

contract ElasticReceiptTokenUpgradeableMock is
    ElasticReceiptTokenUpgradeable
{
    // The token's underlier.
    // Is of type ERC20.
    address public underlier;

    function init(
        address underlier_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external {
        __ElasticReceiptToken_init(name_, symbol_, decimals_);

        underlier = underlier_;
    }

    function _supplyTarget()
        internal
        view
        override(ElasticReceiptTokenBase)
        returns (uint)
    {
        return ERC20(underlier).balanceOf(address(this));
    }

    function mint(uint tokens) external {
        super._mint(msg.sender, tokens);
        ERC20(underlier).transferFrom(msg.sender, address(this), tokens);
    }

    function burn(uint erts) external {
        erts = super._burn(msg.sender, erts);
        ERC20(underlier).transfer(msg.sender, erts);
    }
}
