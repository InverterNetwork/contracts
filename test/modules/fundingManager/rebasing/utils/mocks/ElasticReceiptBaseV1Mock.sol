// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {ElasticReceiptBase_v1} from
    "@fm/rebasing/abstracts/ElasticReceiptBase_v1.sol";

contract ElasticReceiptBaseV1Mock is ElasticReceiptBase_v1 {
    // The token's underlier.
    // Is of type ERC20.
    address public underlier;

    function setUnderlier(address _underlier) public {
        underlier = _underlier;
    }

    function public__ElasticReceiptBase_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        __ElasticReceiptBase_init(name_, symbol_, decimals_);
    }

    function _supplyTarget()
        internal
        view
        override(ElasticReceiptBase_v1)
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
