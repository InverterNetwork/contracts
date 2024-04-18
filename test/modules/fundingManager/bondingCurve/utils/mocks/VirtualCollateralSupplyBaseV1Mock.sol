// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/abstracts/VirtualCollateralSupplyBase_v1.sol";

contract VirtualCollateralSupplyBaseV1Mock is VirtualCollateralSupplyBase_v1 {
    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualCollateralSupplyBase_v1)
    {
        _setVirtualCollateralSupply(_virtualSupply);
    }

    function addVirtualCollateralAmount(uint _amount) external {
        super._addVirtualCollateralAmount(_amount);
    }

    function subVirtualCollateralAmount(uint _amount) external {
        super._subVirtualCollateralAmount(_amount);
    }
}
