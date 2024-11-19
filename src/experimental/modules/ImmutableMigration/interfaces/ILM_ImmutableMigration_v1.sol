// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

interface ILM_ImmutableMigration_v1 {
    function buyForUpTo(address recipient, uint amountIn, uint minAmountOut)
        external;
}
