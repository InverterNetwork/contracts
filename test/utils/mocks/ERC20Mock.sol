// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    mapping(address => bool) blockedAddresses;

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {}

    function mint(address to, uint value) public {
        _mint(to, value);
    }

    function burn(address from, uint value) public {
        _burn(from, value);
    }

    function blockAddress(address user) public {
        blockedAddresses[user] = true;
    }

    function unblockAddress(address user) public {
        blockedAddresses[user] = false;
    }

    function isBlockedAddress(address user) public view returns (bool) {
        return blockedAddresses[user];
    }

    function transfer(address to, uint amount) public override returns (bool) {
        require(!isBlockedAddress(to), "address blocked");
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint amount)
        public
        override
        returns (bool)
    {
        require(!isBlockedAddress(to), "address blocked");
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
}
