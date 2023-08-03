// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {VirtualSupplyTokenUpgradeable} from
    "src/modules/fundingManager/token/VirtualSupplyTokenUpgradeable.sol";

contract VirtualSupplyTokenUpgradeableMock is VirtualSupplyTokenUpgradeable {
    function init(
        string memory name_,
        string memory symbol_,
        uint initialSupply_
    ) external initializer {
        __VirtualSupplyToken_init(name_, symbol_, initialSupply_);
    }

    function setVirtualSupply(uint _newSupply) public {
        _setVirtualSupply(_newSupply);
    }
}
