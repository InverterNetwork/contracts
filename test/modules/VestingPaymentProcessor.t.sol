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
                recipient, amount, (block.timestamp + (7 days))
            );
        }

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        vm.warp(block.timestamp + (7 days) + 1);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]);

            vm.prank(address(recipient));
            paymentProcessor.claim(paymentClient);

            // Check correct balances.
            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(paymentProcessor.releasable(address(recipient)), 0);
        }

        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }

    // Sanity check
/*     function testVestingCalculation(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        vm.assume(recipients.length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts);

        for (uint i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = amounts[i];

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + 1000)
            );
        }

        paymentProcessor.processPayments(paymentClient);
        vm.warp(block.timestamp + 500);

        for (uint i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = amounts[i] / 2;

            assertEq(
                amount,
                paymentProcessor.vestedAmount(block.timestamp, recipient)
            );
        }
    }
 */
         function testUpdateFinishedPayments(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        //workers who were paid before get new payment.
        //@todo
    }

    function testUpdateRunningPayments(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        //we create a set of payments
        // before the period finishes, we change them and assign new amounts+release schedule
        // workers get all the funds that had vested, and the new ones work as expected.

        vm.assume(recipients.length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]*2);

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + 400)
            );
        }

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        vm.warp(block.timestamp + 200);


        //check how much each address can claim:
        uint[] memory claims = new uint[](recipients.length);
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            claims[i] = paymentProcessor.vestedAmount(block.timestamp, recipient);
            assertEq(claims[i], amounts[i]);
        }

        //add a modified round of vesting (but don't process it yet):
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint newAmount = uint(amounts[i]*3);

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, newAmount, (block.timestamp + (6 days))
            );
        }

        // Call processPayments again.
        paymentProcessor.processPayments(paymentClient);


        //we check everybody received what they were owed and can't claim for the new one
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            assertEq(_token.balanceOf(recipient), claims[i]);
            assertEq(paymentProcessor.vestedAmount(block.timestamp,recipient), 0);
        }

        //at the end of the new period, everybody was only able to claim the new salary + what they earned before.
        vm.warp(block.timestamp + (6 days) + 1);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]*4);

            vm.prank(address(recipient));
            paymentProcessor.claim(paymentClient);

            // Check that balances are correct and that noody can claim anything else 
            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(paymentProcessor.releasable(address(recipient)), 0);
        }

        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
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

    function assumeValidDurations(uint64[] memory durations) public {
        for (uint i; i < durations.length; i++) {
            vm.assume(durations[i] != 0);
        }
    }
}
