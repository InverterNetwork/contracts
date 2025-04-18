// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract LM_PC_FundingPot_v1ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function buyFor(address to, uint value, uint minTokens) public {
        _mint(to, value);
    }
}
