// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

/**
 * @title DexAdapter_v1
 * @notice Abstract contract defining interface for DEX adapters
 * @dev This contract defines the base functionality that DEX adapters must implement
 */
abstract contract DexAdapter_v1 {
    /**
     * @notice Creates a new liquidity pool and adds initial liquidity
     * @param tokenA The first token in the pair
     * @param tokenB The second token in the pair
     * @param amountADesired The amount of tokenA to add as liquidity
     * @param amountBDesired The amount of tokenB to add as liquidity
     * @param amountAMin The minimum amount of tokenA to add as liquidity
     * @param amountBMin The minimum amount of tokenB to add as liquidity
     * @param to The address that will receive the liquidity tokens
     * @return liquidity The amount of liquidity tokens minted
     */
    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to
    ) external virtual returns (uint liquidity);
}
