// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IUniswapV2Factory} from "@univ2core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@univ2peri/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {DexAdapter_v1} from "../abstracts/DexAdapter_v1.sol";

/**
 * @title UniswapV2Adapter
 * @notice Helper contract for creating Uniswap V2 pools and adding initial liquidity
 * @dev This contract is used by the LM_ImmutableMigration_v1 contract
 */
contract UniswapV2Adapter is DexAdapter_v1 {
    /// @notice The Uniswap V2 Factory contract
    IUniswapV2Factory public immutable factory;

    /// @notice The Uniswap V2 Router contract
    IUniswapV2Router02 public immutable router;

    /**
     * @notice Constructor
     * @param factory_ The Uniswap V2 Factory contract address
     * @param router_ The Uniswap V2 Router contract address
     */
    constructor(address factory_, address router_) {
        factory = IUniswapV2Factory(factory_);
        router = IUniswapV2Router02(router_);
    }

    /**
     * @notice Creates a new Uniswap V2 pool and adds initial liquidity
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
    ) external override returns (uint liquidity) {
        // Create the pair if it doesn't exist
        if (factory.getPair(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }

        // Add liquidity through the router
        (,, liquidity) = router.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            block.timestamp
        );
    }
}
