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

    function testInit() public override(ModuleTest) {
        assertEq(address(paymentProcessor.token()), address(_token));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        paymentProcessor.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Test: Payment Processing

    function testProcessPayments(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        speedRunVestingAndClaim(recipients, amounts, durations);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]);

            // Check correct balances.
            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(paymentProcessor.releasable(address(recipient)), 0);
        }

        // No funds left in the PaymentClient
        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }

    function testProcessPaymentsDoesNotOVerwriteIfThereAreNoNewOrders(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        speedRunVestingAndClaim(recipients, amounts, durations);

        //We run process payments again, but since there are no new orders, nothing should happen.
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]);

            // Check that the vesting is still in state
            assertEq(
                paymentProcessor.vestedAmount(
                    address(recipient), block.timestamp
                ),
                amount
            );
        }
    }

    // Sanity Math Check
    function testVestingCalculation(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        vm.assume(recipients.length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);

        uint start = block.timestamp;
        uint duration = 1 weeks;

        for (uint i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = amounts[i];

            // Add payment order to client.
            paymentClient.addPaymentOrder(recipient, amount, (start + duration));
        }

        paymentProcessor.processPayments(paymentClient);

        for (uint z = 0; z <= duration; z += 1 hours) {
            //we check each hour
            vm.warp(start + z);

            for (uint i = 0; i < recipients.length; i++) {
                address recipient = recipients[i];
                uint claimableAmt = amounts[i] * z / duration;

                assertEq(claimableAmt, paymentProcessor.releasable(recipient));
            }
        }
    }

    //This test creates a new set of payments in a client which finished all running payments. one possible case would be a proposal that finishes all milestones succesfully and then gets "restarted" some time later
    function testUpdateFinishedPayments(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        speedRunVestingAndClaim(recipients, amounts, durations);

        vm.warp(block.timestamp + 52 weeks);

        speedRunVestingAndClaim(recipients, amounts, durations);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]) * 2; //we paid two rounds

            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(paymentProcessor.releasable(address(recipient)), 0);
        }

        // No funds left in the PaymentClient
        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }

    //This test creates a new set of payments in a client which finished all running payments.
    //one possible case would be a proposal that finishes all milestones succesfully and then gets "restarted" some time later
    function testCancelRunningPayments(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        uint max_duration = uint(durations[0]);
        uint total_amount;
        // add payment orders
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            total_amount += amounts[i];

            if (durations[i] > max_duration) {
                max_duration = durations[i];
            }

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amounts[i], (block.timestamp + durations[i])
            );
        }

        // make sure all the balances are transfered to paymentClient
        assertTrue(_token.balanceOf(address(paymentClient)) == total_amount);

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        // FF to half the max_duration
        vm.warp(max_duration / 2);

        // calling cancelRunningPayments also calls claim() so no need to repeat?
        paymentProcessor.cancelRunningPayments(paymentClient);

        // measure recipients balances before attempting second claim.
        uint[] memory balancesBefore = new uint256[](recipients.length);
        for (uint i; i < recipients.length; i++) {
            vm.prank(recipients[i]);
            paymentProcessor.claim(paymentClient);

            balancesBefore[i] = _token.balanceOf(recipients[i]);
        }

        // skip to end of max_duration
        vm.warp(max_duration / 2);

        // make sure recipients cant claim 2nd time after cancelRunningPayments.
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];

            vm.prank(recipient);
            paymentProcessor.claim(paymentClient);

            uint balanceAfter = _token.balanceOf(recipient);

            assertEq(balancesBefore[i], balanceAfter);
            assertEq(paymentProcessor.releasable(recipient), 0);
        }
    }

    //we create a set of payments, but befor they finish, we supply a new set of orders.
    //Intended behavior is:
    //  - workers get all the funds they already had earned (but maybe not claimed)
    //  - Their remaining payment gets cancelled and substituted by the new one
    function testUpdateRunningPayments(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        vm.assume(recipients.length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);

        //In this case, we want to specifiy the same duration for everbody:
        uint duration = 4 weeks;

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]) * 2;

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + duration)
            );
        }

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        vm.warp(block.timestamp + 2 weeks);

        //check how much each address can claim:
        uint[] memory claims = new uint[](recipients.length);
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            claims[i] =
                paymentProcessor.vestedAmount(recipient, block.timestamp);
            assertEq(claims[i], amounts[i]);
        }

        //add a modified round of vesting with different amount/duration (but don't process it yet):
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint newAmount = uint(amounts[i]) * 3;

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, newAmount, (block.timestamp + (duration * 3))
            );
        }

        // Call processPayments again.
        paymentProcessor.processPayments(paymentClient);

        //we check everybody received what they were owed and can't claim for the new one
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            assertEq(_token.balanceOf(recipient), claims[i]);
            assertEq(
                paymentProcessor.vestedAmount(recipient, block.timestamp), 0
            );
        }

        //at the end of the new period, everybody was only able to claim the new salary + what they earned before.
        vm.warp(block.timestamp + (duration * 3) + 1);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]) * 4;

            vm.prank(address(recipient));
            paymentProcessor.claim(paymentClient);

            // Check that balances are correct and that noody can claim anything else
            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(paymentProcessor.releasable(address(recipient)), 0);
        }

        //No funds remain in the PaymentClient
        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }

    function testBlockedAddressCantClaim() public {
        address recipient = address(0xBABE);
        blockAddress(recipient);

        uint amount = 10 ether;
        uint duration = 10 days;

        paymentClient.addPaymentOrder(
            recipient, amount, (block.timestamp + duration)
        );

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        vm.warp(block.timestamp + duration + 1);

        vm.prank(recipient);
        paymentProcessor.claim(paymentClient);

        // after failed claim attempt receiver should have 0 token,
        // while VPP should move recipient's balances from 'releasable' to 'unclaimable'
        assertEq(_token.balanceOf(address(recipient)), 0);
        assertEq(paymentProcessor.releasable(address(recipient)), 0);
        assertEq(paymentProcessor.unclaimable(recipient), amount);

        unblockAddress(recipient);

        vm.prank(recipient);
        paymentProcessor.claim(paymentClient);

        // after successful claim attempt receiver should receive full amount,
        // while both 'releasable' and 'unclaimable' recipient's amounts should be 0
        assertEq(_token.balanceOf(address(recipient)), amount);
        assertEq(paymentProcessor.releasable(address(recipient)), 0);
        assertEq(paymentProcessor.unclaimable(recipient), 0);

    }

    //--------------------------------------------------------------------------
    // Helper functions

    // Speedruns a round of vesting + claiming
    // note Neither checks the inputs nor verifies results
    function speedRunVestingAndClaim(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) internal {
        uint max_time = uint(durations[0]);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]);
            uint time = uint(durations[i]);

            if (time > max_time) {
                max_time = time;
            }

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + time)
            );
        }

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        vm.warp(block.timestamp + max_time + 1);

        for (uint i; i < recipients.length; i++) {
            vm.prank(address(recipients[i]));
            paymentProcessor.claim(paymentClient);
        }
    }

    function blockAddress(address blockedAddress) internal {
        _token.blockAddress(blockedAddress);
        bool blocked = _token.isBlockedAddress(blockedAddress);
        assertTrue(blocked);
    }

    function unblockAddress(address blockedAddress) internal {
        _token.unblockAddress(blockedAddress);
        bool blocked = _token.isBlockedAddress(blockedAddress);
        assertFalse(blocked);
    }

    //--------------------------------------------------------------------------
    // Fuzzing Validation Helpers

    mapping(address => bool) recipientCache;

    function assumeValidRecipients(address[] memory addrs) public {
        vm.assume(addrs.length != 0);
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

    // note By only checking the values we'll use, we avoid unnecessary rejections
    function assumeValidAmounts(uint128[] memory amounts, uint checkUpTo)
        public
    {
        vm.assume(amounts.length != 0);
        for (uint i; i < checkUpTo; i++) {
            vm.assume(amounts[i] != 0);
        }
    }

    // note By only checking the values we'll use, we avoid unnecessary rejections
    function assumeValidDurations(uint64[] memory durations, uint checkUpTo)
        public
    {
        vm.assume(durations.length != 0);
        for (uint i; i < checkUpTo; i++) {
            vm.assume(durations[i] != 0);
        }
    }
}
