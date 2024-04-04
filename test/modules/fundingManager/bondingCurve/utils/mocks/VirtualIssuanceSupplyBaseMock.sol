// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualIssuanceSupplyBase} from
    "src/modules/fundingManager/bondingCurve/abstracts/VirtualIssuanceSupplyBase.sol";

contract VirtualIssuanceSupplyBaseMock is VirtualIssuanceSupplyBase {
    function setVirtualIssuanceSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualIssuanceSupplyBase)
    {
        _setVirtualIssuanceSupply(_virtualSupply);
    }

    function addVirtualTokenAmount(uint _amount) external {
        super._addVirtualTokenAmount(_amount);
    }

    function subVirtualTokenAmount(uint _amount) external {
        super._subVirtualTokenAmount(_amount);
    }
}
