// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// SuT
import {
    VestingPaymentProcessor,
    IPaymentProcessor
} from "src/modules/VestingPaymentProcessor.sol";

// Mocks
import {PaymentClientMock} from
    "test/utils/mocks/modules/mixins/PaymentClientMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract VestingPaymentProcessorTest is ModuleTest {
    // SuT
    VestingPaymentProcessor paymentProcessor;

    // Mocks
    PaymentClientMock paymentClient = new PaymentClientMock(_token);

    function setUp() public {
        address impl = address(new VestingPaymentProcessor());
        paymentProcessor = VestingPaymentProcessor(Clones.clone(impl));

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

    function testProcessPayments(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        vm.assume(recipients.length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]);

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + 100)
            );

            // Call processPayments.
            paymentProcessor.processPayments(paymentClient);

            vm.warp(block.timestamp + 101);
            vm.prank(address(recipient));
            paymentProcessor.claim(paymentClient);

            // Check correct balances.
            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(_token.balanceOf(address(paymentClient)), 0);

            // Invariant: Payment processor does not hold funds.
            assertEq(_token.balanceOf(address(paymentProcessor)), 0);
        }
    }

    function testUpdatePayments(address recipient, uint amount) public {
        // @todo
    }

    mapping(address => bool) recipientCache;

    function assumeValidRecipients(address[] memory addrs) public {
        for (uint i; i < addrs.length; i++) {
            assumeValidRecipient(addrs[i]);

            // Assume contributor address unique.
            vm.assume(!recipientCache[addrs[i]]);

            // Add contributor address to cache.
            recipientCache[addrs[i]] = true;
        }
    }

    function assumeValidRecipient(address a) public {
        address[] memory invalids = createInvalidRecipients();

        for (uint i; i < invalids.length; i++) {
            vm.assume(a != invalids[i]);
        }
    }

    function createInvalidRecipients() public view returns (address[] memory) {
        address[] memory invalids = new address[](5);

        invalids[0] = address(0);
        invalids[1] = address(_proposal);
        invalids[2] = address(paymentProcessor);
        invalids[3] = address(paymentClient);
        invalids[4] = address(this);

        return invalids;
    }

    function assumeValidAmounts(uint128[] memory amounts) public {
        for (uint i; i < amounts.length; i++) {
            vm.assume(amounts[i] != 0);
        }
    }
}
