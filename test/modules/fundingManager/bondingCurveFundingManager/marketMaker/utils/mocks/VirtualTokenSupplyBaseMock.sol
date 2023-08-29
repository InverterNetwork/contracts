// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualTokenSupplyBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/VirtualTokenSupplyBase.sol";

contract VirtualTokenSupplyBaseMock is VirtualTokenSupplyBase {
    function setVirtualTokenSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualTokenSupplyBase)
    {
        _setVirtualTokenSupply(_virtualSupply);
    }

    function addTokenAmount(uint _amount) external {
        super._addVirtualTokenAmount(_amount);
    }

    function subTokenAmount(uint _amount) external {
        super._subVirtualTokenAmount(_amount);
    }
}
