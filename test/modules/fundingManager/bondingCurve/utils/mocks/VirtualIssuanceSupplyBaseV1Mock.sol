// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/abstracts/VirtualIssuanceSupplyBase_v1.sol";

contract VirtualIssuanceSupplyBaseV1Mock is VirtualIssuanceSupplyBase_v1 {
    function setVirtualIssuanceSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualIssuanceSupplyBase_v1)
    {
        _setVirtualIssuanceSupply(_virtualSupply);
    }

    function addVirtualIssuanceAmount(uint _amount) external {
        super._addVirtualIssuanceAmount(_amount);
    }

    function subVirtualIssuanceAmount(uint _amount) external {
        super._subVirtualIssuanceAmount(_amount);
    }
}
