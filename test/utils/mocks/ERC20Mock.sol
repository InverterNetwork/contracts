// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    mapping(address => bool) blockedAddresses;
    bool returnFalse;

    bool reentrancyOnTransfer;

    bytes reentrancyCallData;

    bool public callSuccessful;

    bytes public callData;

    uint8 internal _decimals = 18;

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

    function toggleReturnFalse() public {
        returnFalse = !returnFalse;
    }

    function setReentrancyOnTransfer(bytes calldata data) public {
        reentrancyOnTransfer = true;
        reentrancyCallData = data;
    }

    function isBlockedAddress(address user) public view returns (bool) {
        return blockedAddresses[user];
    }

    function transfer(address to, uint amount) public override returns (bool) {
        if (returnFalse) {
            return false;
        }
        require(!isBlockedAddress(to), "address blocked");
        address owner = _msgSender();
        _transfer(owner, to, amount);

        // Quite dirty but this should do the trick of testing attempted reentrancy
        if (reentrancyOnTransfer) {
            (bool success, bytes memory data) =
                msg.sender.call(reentrancyCallData);
            callSuccessful = success;
            callData = data;
        }

        return true;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 newDecimals) public virtual {
        _decimals = newDecimals;
    }

    function transferFrom(address from, address to, uint amount)
        public
        override
        returns (bool)
    {
        if (returnFalse) {
            return false;
        }
        require(!isBlockedAddress(to), "address blocked");
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);

        // Quite dirty but this should do the trick of testing attempted reentrancy
        if (reentrancyOnTransfer) {
            (bool success, bytes memory data) =
                msg.sender.call(reentrancyCallData);
            callSuccessful = success;
            callData = data;
        }

        return true;
    }
}
