// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

abstract contract VirtualCollateralSupplyBase {
    uint internal virtualCollateralSupply;

    function getVirtualCollateralSupply() external view returns (uint) {
        return _getVirtualCollateralSupply();
    }

    function _addCollateralAmount(uint _amount) internal {
        virtualCollateralSupply += _amount;
    }

    function _subCollateralAmount(uint _amount) internal {
        virtualCollateralSupply -= _amount;
    }

    function _setVirtualCollateralSupply(uint _virtualSupply) internal {
        virtualCollateralSupply = _virtualSupply;
    }

    function _getVirtualCollateralSupply() internal view returns (uint) {
        return virtualCollateralSupply;
    }
}
