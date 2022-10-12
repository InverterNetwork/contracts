// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IPayer} from "src/interfaces/IPayer.sol";

contract PayerMock is IPayer {
    IERC20 private _paymentToken;

    function setPaymentToken(IERC20 token) external {
        _paymentToken = token;
    }

    //--------------------------------------------------------------------------
    // IPayer Functions

    function pay(address recipient, uint amount, bytes memory details)
        external
    {}

    function paymentToken() external view returns (IERC20) {
        return _paymentToken;
    }
}
