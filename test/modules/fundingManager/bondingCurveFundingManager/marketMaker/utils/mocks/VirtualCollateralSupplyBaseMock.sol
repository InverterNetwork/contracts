// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualCollateralSupplyBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/VirtualCollateralSupplyBase.sol";

contract VirtualCollateralSupplyBaseMock is VirtualCollateralSupplyBase {
    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualCollateralSupplyBase)
    {
        _setVirtualCollateralSupply(_virtualSupply);
    }

    function addCollateralAmount(uint _amount) external {
        super._addVirtualCollateralAmount(_amount);
    }

    function subCollateralAmount(uint _amount) external {
        super._subVirtualCollateralAmount(_amount);
    }
}
