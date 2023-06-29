// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC721} from "@oz/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
    uint public idCounter;

    mapping(address => bool) blockedAddresses;

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {}

    function mint(address to) public {
        _mint(to, idCounter);
        idCounter = idCounter + 1;
    }

    function burn(uint tokenId) public {
        _burn(tokenId);
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

    function transferFrom(address from, address to, uint tokenId)
        public
        override
    {
        require(!isBlockedAddress(to), "address blocked");
        _transfer(from, to, tokenId);
    }
}
