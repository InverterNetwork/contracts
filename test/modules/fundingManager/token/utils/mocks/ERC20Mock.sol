// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        // NO-OP
    }

    function mint(address to, uint value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint value) public virtual {
        _burn(from, value);
    }
}
