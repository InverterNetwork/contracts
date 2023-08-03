// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {VirtualSupplyBase} from
    "src/modules/fundingManager/token/VirtualSupplyBase.sol";
import {ERC20Upgradeable} from "@oz-up/token/ERC20/ERC20Upgradeable.sol";

abstract contract VirtualSupplyTokenUpgradeable is
    VirtualSupplyBase,
    ERC20Upgradeable
{
    //--------------------------------------------------------------------------
    // Initialization

    /// @dev Initializes the contracts
    function __VirtualSupplyToken_init(
        string memory name_,
        string memory symbol_,
        uint initialSupply_
    ) internal {
        __ERC20_init(name_, symbol_);
        _setVirtualSupply(initialSupply_);
    }
}
