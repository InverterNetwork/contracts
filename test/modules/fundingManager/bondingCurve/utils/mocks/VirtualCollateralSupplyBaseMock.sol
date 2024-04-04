// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualCollateralSupplyBase} from
    "src/modules/fundingManager/bondingCurve/abstracts/VirtualCollateralSupplyBase.sol";

contract VirtualCollateralSupplyBaseMock is VirtualCollateralSupplyBase {
    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualCollateralSupplyBase)
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
