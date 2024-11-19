// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/console.sol";

import {IUniswapV2Factory} from "@univ2core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "@univ2peri/interfaces/IUniswapV2Router01.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IDexAdapter_v1} from
    "src/experimental/modules/ImmutableMigration/interfaces/IDexAdapter_v1.sol";

/**
 * @title UniswapV2Adapter
 * @notice Helper contract for creating Uniswap V2 pools and adding initial liquidity
 * @dev This contract is used by the LM_ImmutableMigration_v1 contract
 */
contract UniswapV2Adapter is IDexAdapter_v1 {
    /// @notice The Uniswap V2 Factory contract
    IUniswapV2Factory public immutable factory;

    /// @notice The Uniswap V2 Router contract
    IUniswapV2Router01 public immutable router;

    /**
     * @notice Constructor
     * @param factory_ The Uniswap V2 Factory contract address
     * @param router_ The Uniswap V2 Router contract address
     */
    constructor(address factory_, address router_) {
        factory = IUniswapV2Factory(factory_);
        router = IUniswapV2Router01(router_);
    }

    function createLiquidity(address tokenA, address tokenB, address to)
        external
        returns (uint liquidity)
    {
        factory.createPair(tokenA, tokenB);

        uint amountA = IERC20(tokenA).balanceOf(address(this));
        uint amountB = IERC20(tokenB).balanceOf(address(this));

        IERC20(tokenA).approve(address(router), amountA);
        IERC20(tokenB).approve(address(router), amountB);

        // Add liquidity through the router
        router.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            amountA * 95 / 100,
            amountB * 95 / 100,
            to,
            block.timestamp + 10 minutes
        );
    }
}
