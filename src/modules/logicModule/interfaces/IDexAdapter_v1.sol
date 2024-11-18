// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

/**
 * @title   DEX Adapter Interface
 * @notice  Interface for DEX adapters that handle token swaps
 * @dev     Implementations should handle interactions with specific DEXes
 * @custom:security-contact security@inverter.network
 * @author  Inverter Network
 */
interface IDexAdapter_v1 {
    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens that must be received
     * @param path The token swap path
     * @param to Recipient of the output tokens
     * @param deadline Unix timestamp after which the transaction will revert
     * @return amounts The amounts of tokens swapped
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /**
     * @notice Gets the amounts out for a token swap
     * @param amountIn The amount of input tokens
     * @param path The token swap path
     * @return amounts The amounts of tokens that would be received
     */
    function getAmountsOut(uint amountIn, address[] calldata path)
        external
        view
        returns (uint[] memory amounts);
}
