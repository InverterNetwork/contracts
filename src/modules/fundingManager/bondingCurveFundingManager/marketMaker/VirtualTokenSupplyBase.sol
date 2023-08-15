// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {IVirtualTokenSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";

abstract contract VirtualTokenSupplyBase is IVirtualTokenSupply {
    uint internal virtualTokenSupply;
    uint private constant MAX_UINT = 2 ** 256 - 1;

    function setVirtualTokenSupply(uint _virtualSupply) external virtual;

    function getVirtualTokenSupply() external view returns (uint) {
        return _getVirtualTokenSupply();
    }

    function _addTokenAmount(uint _amount) internal {
        if (_amount > (MAX_UINT - virtualTokenSupply)) {
            revert VirtualTokenSupply_AddResultsInOverflow();
        }
        virtualTokenSupply += _amount;
    }

    function _subTokenAmount(uint _amount) internal {
        if (_amount > virtualTokenSupply) {
            revert VirtualTokenSupply__SubtractResultsInUnderflow();
        }

        virtualTokenSupply -= _amount;
    }

    function _setVirtualTokenSupply(uint _virtualSupply) internal {
        virtualTokenSupply += _virtualSupply;
    }

    function _getVirtualTokenSupply() internal view returns (uint) {
        return virtualTokenSupply;
    }
}
