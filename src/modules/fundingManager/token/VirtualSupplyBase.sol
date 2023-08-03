// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IVirtualSupplyToken} from
    "src/modules/fundingManager/token/IVirtualSupplyToken.sol";

abstract contract VirtualSupplyBase is IVirtualSupplyToken {
    uint internal _virtualSupply;

    /// @inheritdoc IVirtualSupplyToken
    function totalVirtualSupply() public view returns (uint) {
        return _virtualSupply;
    }

    function _setVirtualSupply(uint _newSupply) internal {
        _virtualSupply = _newSupply;
    }
}
