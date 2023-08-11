// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

abstract contract VirtualTokenSupplyBase {
    uint internal virtualTokenSupply;

    function getVirtualTokenSupply() external view returns (uint) {
        return _getVirtualTokenSupply();
    }

    function _addTokenAmount(uint _amount) internal {
        virtualTokenSupply += _amount;
    }

    function _subTokenAmount(uint _amount) internal {
        virtualTokenSupply -= _amount;
    }

    function _setVirtualTokenSupply(uint _virtualSupply) internal {
        virtualTokenSupply += _virtualSupply;
    }

    function _getVirtualTokenSupply() internal view returns (uint) {
        return virtualTokenSupply;
    }
}
