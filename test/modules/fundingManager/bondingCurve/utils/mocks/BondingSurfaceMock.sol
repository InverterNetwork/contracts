// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BondingSurface} from
    "src/modules/fundingManager/bondingCurve/formulas/BondingSurface.sol";

contract BondingSurfaceMock is BondingSurface {
    function call_inverse(uint x) external pure returns (uint res) {
        return _inverse(x);
    }
}
