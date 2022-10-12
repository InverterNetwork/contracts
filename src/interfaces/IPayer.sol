// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IPayer {
    /// @notice Pays `amount` of tokens to `recipient`.
    /// @dev Depending on the exact implementation, raw byte data can be
    ///      provided to specify more payment details.
    /// @param recipient The payment recipient address.
    /// @param amount The amount of token to pay.
    /// @param details Details for the payment. Dependent on the exact
    ///                implementation.
    function pay(address recipient, uint amount, bytes memory details)
        external;

    /// @notice The {IERC20} token used for payments.
    /// @dev MUST not change after initialization.
    function paymentToken() external view returns (IERC20);
}
