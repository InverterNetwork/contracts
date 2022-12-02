// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {}

    function mint(address to, uint value) public {
        _mint(to, value);
    }

    function burn(address from, uint value) public {
        _burn(from, value);
    }
}
