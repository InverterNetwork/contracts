// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

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
    PaymentProcessor paymentProcessor;

    // Mocks
    PaymentClientMock paymentClient = new PaymentClientMock(_token);

    function setUp() public {
        address impl = address(new PaymentProcessor());
        paymentProcessor = PaymentProcessor(Clones.clone(impl));

        _setUpProposal(paymentProcessor);

        paymentProcessor.init(_proposal, _METADATA, bytes(""));

        paymentClient.setIsAuthorized(address(paymentProcessor), true);
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
        vm.assume(recipient != address(paymentClient));
        vm.assume(recipient != address(0));
        vm.assume(amount != 0);

        // Add payment order to client.
        paymentClient.addPaymentOrder(recipient, amount, block.timestamp);

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        // Check correct balances.
        assertEq(_token.balanceOf(address(recipient)), amount);
        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }
}
