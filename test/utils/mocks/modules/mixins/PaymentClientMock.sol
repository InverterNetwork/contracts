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

    function addPaymentOrders(
        address[] memory recipients,
        uint[] memory amounts,
        uint[] memory dueTos
    ) external {
        _addPaymentOrders(recipients, amounts, dueTos);
    }

    function addIdenticalPaymentOrders(
        address[] memory recipients,
        uint amount,
        uint dueTo
    ) external {
        _addIdenticalPaymentOrders(recipients, amount, dueTo);
    }

    //--------------------------------------------------------------------------
    // IPaymentClient Overriden Functions

    function _ensureTokenBalance(uint amount)
        internal
        override(PaymentClient)
    {
        if (token.balanceOf(address(this)) >= amount) {
            return;
        } else {
            uint amtToMint = amount - token.balanceOf(address(this));
            token.mint(address(this), amtToMint);
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override(PaymentClient)
    {
        token.approve(address(spender), amount);
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor)
        internal
        view
        override(PaymentClient)
        returns (bool)
    {
        return authorized[msg.sender];
    }
}
