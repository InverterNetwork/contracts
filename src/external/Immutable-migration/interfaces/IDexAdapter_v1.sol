// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IDexAdapter_v1 {
    function createLiquidity(address tokenA, address tokenB, address to)
        external
        returns (address pool);
}
