// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// SuT
import {
    PaymentClient, IPaymentClient
} from "src/modules/mixins/PaymentClient.sol";

// Internal Interfaces
import {IPaymentProcessor} from "src/modules/IPaymentProcessor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract PaymentClientMock is PaymentClient {
    ERC20Mock token;

    mapping(address => bool) authorized;

    constructor(ERC20Mock token_) {
        token = token_;
    }

    //--------------------------------------------------------------------------
    // Mock Functions

    function setIsAuthorized(address who, bool to) external {
        authorized[who] = to;
    }

    //--------------------------------------------------------------------------
    // IPaymentClient Wrapper Functions

    function addPaymentOrder(address recipient, uint amount, uint dueTo)
        external
    {
        _addPaymentOrder(recipient, amount, dueTo);
    }

    //--------------------------------------------------------------------------
    // IPaymentClient Overriden Functions

    function _ensureTokenBalance(uint amount)
        internal
        override (PaymentClient)
    {
        token.mint(address(this), amount);
    }

    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override (PaymentClient)
    {
        token.approve(address(spender), amount);
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor)
        internal
        view
        override (PaymentClient)
        returns (bool)
    {
        return authorized[msg.sender];
    }
}
