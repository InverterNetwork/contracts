// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// SuT
import {
    PaymentProcessor,
    IPaymentProcessor
} from "src/modules/PaymentProcessor.sol";

// Mocks
import {PaymentClientMock} from
    "test/utils/mocks/modules/mixins/PaymentClientMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PaymentProcessorTest is ModuleTest {
    // SuT
    PaymentProcessor paymentProcessor = new PaymentProcessor();

    // Mocks
    PaymentClientMock client = new PaymentClientMock();

    function setUp() public {
        _setUpProposal(paymentProcessor);

        paymentProcessor.init(_proposal, _METADATA, bytes(""));

        // Note that no authorization is needed.
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override (ModuleTest) {
        assertEq(address(paymentProcessor.token()), address(_token));
    }

    function testReinitFails() public override (ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        paymentProcessor.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Test: Payment Processing

    function testProcessPayments(address recipient, uint amount) public {
        vm.assume(recipient != address(paymentProcessor));
        vm.assume(recipient != address(0));
        vm.assume(amount != 0);

        // Add payment order to client.
        client.addPaymentOrder(recipient, amount, block.timestamp);

        // Mint tokens to client.
        _token.mint(address(client), amount);

        // Approve amount of tokens from client for paymentProcessor.
        client.approve(_token, address(paymentProcessor), amount);

        // Call processPayments
        paymentProcessor.processPayments(client);

        // Check correct balances.
        assertEq(_token.balanceOf(address(recipient)), amount);
        assertEq(_token.balanceOf(address(client)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }
}
