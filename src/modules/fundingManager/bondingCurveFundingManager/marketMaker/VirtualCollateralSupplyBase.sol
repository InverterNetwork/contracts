// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {IVirtualCollateralSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualCollateralSupply.sol";

abstract contract VirtualCollateralSupplyBase is IVirtualCollateralSupply {
    uint internal virtualCollateralSupply;
    uint private constant MAX_UINT = 2 * 256 - 1;

    function setVirtualCollateralSupply(uint _virtualSupply) external virtual;

    function getVirtualCollateralSupply() external view returns (uint) {
        return _getVirtualCollateralSupply();
    }

    function _addCollateralAmount(uint _amount) internal {
        if (_amount > (MAX_UINT - virtualCollateralSupply)) {
            revert VirtualCollateralSupply_AddResultsInOverflow();
        }

        virtualCollateralSupply += _amount;
    }

    function _subCollateralAmount(uint _amount) internal {
        if (_amount > virtualCollateralSupply) {
            revert VirtualCollateralSupply__SubtractResultsInUnderflow();
        }

        virtualCollateralSupply -= _amount;
    }

    function _setVirtualCollateralSupply(uint _virtualSupply) internal {
        virtualCollateralSupply = _virtualSupply;
    }

    function _getVirtualCollateralSupply() internal view returns (uint) {
        return virtualCollateralSupply;
    }
}
