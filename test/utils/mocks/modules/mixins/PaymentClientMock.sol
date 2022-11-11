// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IPaymentClient} from "src/modules/mixins/PaymentClient.sol";

contract PaymentClientMock is IPaymentClient {
    IPaymentClient.PaymentOrder[] internal _orders;

    uint internal _outstandingTokenAmount;

    function addPaymentOrder(address recipient, uint amount, uint dueTo)
        external
    {
        _outstandingTokenAmount += amount;

        _orders.push(
            IPaymentClient.PaymentOrder(
                recipient, amount, block.timestamp, dueTo
            )
        );
    }

    function approve(IERC20 token, address spender, uint amount) external {
        token.approve(spender, amount);
    }

    //--------------------------------------------------------------------------
    // IPaymentClient Functions

    function paymentOrders() external view returns (PaymentOrder[] memory) {
        return _orders;
    }

    function collectPaymentOrders()
        external
        returns (PaymentOrder[] memory, uint)
    {
        // Create a copy of all orders to return.
        PaymentOrder[] memory copy = new PaymentOrder[](_orders.length);
        for (uint i; i < _orders.length; i++) {
            copy[i] = _orders[i];
        }

        // Delete all outstanding orders.
        delete _orders;

        // Cache outstanding token amount.
        uint outstandingTokenAmountCache = _outstandingTokenAmount;

        // Set outstanding token amount to zero.
        _outstandingTokenAmount = 0;

        // Return copy of orders to payment processor.
        return (copy, outstandingTokenAmountCache);
    }
}
