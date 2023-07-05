// Copyright (C) 2020 d-xo
// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity >=0.6.12;

import {ERC20} from "./ERC20.sol";

contract BlockableToken is ERC20 {
    // --- Access Control ---
    address owner;

    modifier auth() {
        require(msg.sender == owner, "unauthorised");
        _;
    }

    // --- BlockList ---
    mapping(address => bool) blocked;

    function blockUser(address usr) public auth {
        blocked[usr] = true;
    }

    function allow(address usr) public auth {
        blocked[usr] = false;
    }

    // --- Init ---
    constructor(uint _totalSupply) ERC20(_totalSupply) {
        owner = msg.sender;
    }

    // --- Getter ---
    function isBlocked(address usr) public view returns (bool) {
        return blocked[usr];
    }

    // --- Token ---
    function transferFrom(address src, address dst, uint wad)
        public
        override
        returns (bool)
    {
        require(!blocked[src], "source blocked");
        require(!blocked[dst], "destination blocked");
        return super.transferFrom(src, dst, wad);
    }
}
