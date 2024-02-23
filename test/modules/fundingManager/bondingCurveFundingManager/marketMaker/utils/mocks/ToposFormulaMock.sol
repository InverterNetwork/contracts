// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ToposFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/ToposFormula.sol";

contract ToposFormulaMock is ToposFormula {
    function call_inverse(uint x) external pure returns (uint res) {
        return _inverse(x);
    }
}
