// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";

interface INativeIssuance_v1 is IERC20Issuance_v1 {
    //--------------------------------------------------------------------------
    // Events

    /**
     * @dev Emitted when `value` tokens are minted to an account to (`to`).
     *
     * Note that `value` may be zero.
     */
    event Minted(address indexed to, uint value);

    /**
     * @dev Emitted when `value` tokens are burned from an account from (`from`).
     *
     * Note that `value` may be zero.
     */
    event Burned(address indexed from, uint value);

    //--------------------------------------------------------------------------
    // Errors

    error INativeIssuance_v1__NotSupported();
    error INativeIssuance_v1__InvalidAddress();
    error INativeIssuance_v1__InvalidAmount();

    //--------------------------------------------------------------------------
    // Functions

    // Write

    /**
     * @notice Deposits native tokens to be able to burn native tokens from the specified address.
     * @dev    `msg.value` is the amount of native tokens to be deposited.
     * @param  from   The address that will have native tokens deposited for.
     */
    function depositNative(address from) external payable;
}
