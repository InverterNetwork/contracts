// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// SuT
import {
    ConcurrentStreamingPaymentProcessor,
    IPaymentProcessor
} from "src/modules/paymentProcessor/ConcurrentStreamingPaymentProcessor.sol";

// Mocks
import {PaymentClientMock} from
    "test/utils/mocks/modules/mixins/PaymentClientMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ConcurrentStreamingPaymentProcessorTest is ModuleTest {
    // SuT
    ConcurrentStreamingPaymentProcessor paymentProcessor;

    // Mocks
    PaymentClientMock paymentClient = new PaymentClientMock(_token);

    event InvalidStreamingOrderDiscarded(
        address indexed recipient, uint amount, uint start, uint duration
    );

    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint duration,
        uint walletId
    );

    event StreamingPaymentRemoved(
        address indexed paymentClient,
        address indexed recipient,
        uint indexed walletId
    );

    function setUp() public {
        address impl = address(new ConcurrentStreamingPaymentProcessor());
        paymentProcessor =
            ConcurrentStreamingPaymentProcessor(Clones.clone(impl));

        _setUpProposal(paymentProcessor);

        _authorizer.setIsAuthorized(address(this), true);

        _proposal.addModule(address(paymentClient));

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

    function test_processPayments(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        uint max_time = uint(durations[0]);
        uint totalAmount;

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

            totalAmount += amount;
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < recipients.length;) {
            assertTrue(
                paymentProcessor.isActiveContributor(
                    address(paymentClient), recipients[i]
                )
            );
            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient),
                    recipients[i],
                    1 // 1 is the first default wallet ID for all unique recepients
                ),
                0,
                "Nothing would have vested at the start of the vesting duration"
            );
            unchecked {
                ++i;
            }
        }

        assertEq(totalAmount, _token.balanceOf(address(paymentClient)));
    }

    function test_claimVestedAmounts_fullVesting(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        uint max_time = uint(durations[0]);
        uint totalAmount;

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

            totalAmount += amount;
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < recipients.length;) {
            assertTrue(
                paymentProcessor.isActiveContributor(
                    address(paymentClient), recipients[i]
                )
            );
            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient),
                    recipients[i],
                    1 // 1 is the first default wallet ID for all unique recepients
                ),
                0,
                "Nothing would have vested at the start of the vesting duration"
            );
            unchecked {
                ++i;
            }
        }

        assertEq(totalAmount, _token.balanceOf(address(paymentClient)));

        // Moving ahead in time, past the longest vesting period
        vm.warp(block.timestamp + (max_time + 1));

        // All recepients try to claim their vested tokens
        for (uint i; i < recipients.length;) {
            vm.prank(recipients[i]);
            paymentProcessor.claimAll(paymentClient);
            unchecked {
                ++i;
            }
        }

        // Now, all recipients should have their entire vested amount with them
        for (uint i; i < recipients.length;) {
            // Check recipient balance
            assertEq(
                _token.balanceOf(recipients[i]),
                uint(amounts[i]),
                "Vested tokens not received by the contributor"
            );

            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient),
                    recipients[i],
                    1 // 1 is the first default wallet ID for all unique recepients
                ),
                0,
                "All vested amount is already released"
            );

            unchecked {
                ++i;
            }
        }
    }

    function test_processPayments_discardsInvalidPaymentOrders() public {
        address[] memory recipients = createInvalidRecipients();

        uint invalidDur = 0;
        uint invalidAmt = 0;

        vm.warp(1000);
        vm.startPrank(address(paymentClient));
        //we don't mind about adding address(this)in this case
        for (uint i = 0; i < recipients.length - 1; ++i) {
            paymentClient.addPaymentOrderUnchecked(
                recipients[i], 100, (block.timestamp + 100)
            );
        }
        //Expect the correct number and sequence of emits
        for (uint i = 0; i < recipients.length - 1; ++i) {
            vm.expectEmit(true, true, true, true);
            emit InvalidStreamingOrderDiscarded(
                recipients[i], 100, block.timestamp, 100
            );
        }

        // Call processPayments and expect emits
        paymentProcessor.processPayments(paymentClient);

        //add invalid dur process and expect emit
        paymentClient.addPaymentOrderUnchecked(
            address(0xB0B), 100, (block.timestamp + invalidDur)
        );
        vm.expectEmit(true, true, true, true);
        emit InvalidStreamingOrderDiscarded(
            address(0xB0B), 100, block.timestamp, invalidDur
        );
        paymentProcessor.processPayments(paymentClient);

        paymentClient.addPaymentOrderUnchecked(
            address(0xB0B), invalidAmt, (block.timestamp + 100)
        );
        vm.expectEmit(true, true, true, true);
        emit InvalidStreamingOrderDiscarded(
            address(0xB0B), invalidAmt, block.timestamp, 100
        );
        paymentProcessor.processPayments(paymentClient);

        vm.stopPrank();
    }

    function test_processPayments_vestingInfoGetsDeletedPostFullPayment(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        speedRunStreamingAndClaim(recipients, amounts, durations);

        //We run process payments again, but since there are no new orders, nothing should happen.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];

            // Check that the vesting information is deleted once vested tokens are claimed after total vesting duration
            assertEq(
                paymentProcessor.vestedAmountForSpecificWalletId(
                    address(paymentClient),
                    address(recipient),
                    block.timestamp,
                    1
                ),
                0
            );
        }
    }

    function test_processPayments_paymentOrdersAreNotOverwritten(
        uint randomDuration,
        uint randomAmount,
        uint randomDuration_2,
        uint randomAmount_2
    ) public {
        randomDuration = bound(randomDuration, 10, 10_000_000);
        randomAmount = bound(randomAmount, 10, 10_000);
        randomDuration_2 = bound(randomDuration_2, 1000, 10_000_000);
        randomAmount_2 = bound(randomAmount_2, 100, 10_000);

        address contributor1 = makeAddr("contributor1");
        address contributor2 = makeAddr("contributor2");
        address contributor3 = makeAddr("contributor3");
        address contributor4 = makeAddr("contributor4");

        address[3] memory contributorArray_1;
        contributorArray_1[0] = contributor1;
        contributorArray_1[1] = contributor2;
        contributorArray_1[2] = contributor3;

        uint[3] memory durations_1;
        for (uint i; i < 3; i++) {
            durations_1[i] = (randomDuration * (i + 1));
        }

        uint[3] memory amounts_1;
        for (uint i; i < 3; i++) {
            amounts_1[i] = (randomAmount * (i + 1));
        }

        // Add these payment orders to the payment client
        for (uint i; i < 3; i++) {
            address recipient = contributorArray_1[i];
            uint amount = amounts_1[i];
            uint time = durations_1[i];

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + time)
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Let's travel in time, to the point after contributor1's tokens are fully vested.
        // Also, remember, nothing is claimed yet
        vm.warp(block.timestamp + durations_1[0]);

        // Now, the payment client decided to add a few more payment orders (with a few beneficiaries overlapping)
        address[3] memory contributorArray_2;
        contributorArray_2[0] = contributor2;
        contributorArray_2[1] = contributor3;
        contributorArray_2[2] = contributor4;

        uint[3] memory durations_2;
        for (uint i; i < 3; i++) {
            durations_2[i] = (randomDuration_2 * (i + 1));
        }

        uint[3] memory amounts_2;
        for (uint i; i < 3; i++) {
            amounts_2[i] = (randomAmount_2 * (i + 1));
        }

        // Add these payment orders to the payment client
        for (uint i; i < 3; i++) {
            address recipient = contributorArray_2[i];
            uint amount = amounts_2[i];
            uint time = durations_2[i];

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + time)
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Now, let's check whether all vesting informations exist or not
        // checking for contributor2
        ConcurrentStreamingPaymentProcessor.StreamingWallet[] memory
            contributorWallets;
        contributorWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), contributor2
        );

        assertTrue(contributorWallets.length == 2);
        assertEq(
            (contributorWallets[0]._salary + contributorWallets[1]._salary),
            (amounts_1[1] + amounts_2[0]),
            "Improper accounting of orders"
        );

        // checking for contributor3
        contributorWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), contributor3
        );

        assertTrue(contributorWallets.length == 2);
        assertEq(
            (contributorWallets[0]._salary + contributorWallets[1]._salary),
            (amounts_1[2] + amounts_2[1]),
            "Improper accounting of orders"
        );

        // checking for contributor 4
        contributorWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), contributor4
        );

        assertTrue(contributorWallets.length == 1);
        assertEq(
            (contributorWallets[0]._salary),
            (amounts_2[2]),
            "Improper accounting of orders"
        );

        // checking for contributor 1
        contributorWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), contributor1
        );

        assertTrue(contributorWallets.length == 1);
        assertEq(
            (contributorWallets[0]._salary),
            (amounts_1[0]),
            "Improper accounting of orders"
        );
    }

    function test_processPayments_failsWhenCalledByNonModule(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_authorizer));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__OnlyCallableByModule
                    .selector
            )
        );
        paymentProcessor.processPayments(paymentClient);
    }

    function testProcessPaymentsFailsWhenCalledOnOtherClient(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));

        PaymentClientMock otherPaymentClient = new PaymentClientMock(_token);

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.processPayments(otherPaymentClient);
    }

    function test_cancelRunningPayments_allCreatedOrdersGetCancelled(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        vm.assume(recipients.length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);

        uint duration = 4 weeks;

        for (uint i = 0; i < recipients.length; ++i) {
            paymentClient.addPaymentOrder(recipients[i], amounts[i], duration);
        }
        //Expect the correct number and sequence of emits
        for (uint i = 0; i < recipients.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit StreamingPaymentAdded(
                address(paymentClient),
                recipients[i],
                amounts[i],
                block.timestamp,
                duration - block.timestamp,
                1
            );
        }

        // Call processPayments and expect emits
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF to half the max_duration
        vm.warp(block.timestamp + 2 weeks);

        //we expect cancellation events for each payment
        for (uint i = 0; i < recipients.length; ++i) {
            vm.expectEmit(true, true, true, true);
            // we can expect all recipient to be unique due to the call to assumeValidRecipients.
            // Therefore, the walletId of all these contributors would be 1.
            emit StreamingPaymentRemoved(
                address(paymentClient), recipients[i], 1
            );
        }

        // calling cancelRunningPayments
        vm.prank(address(paymentClient));
        paymentProcessor.cancelRunningPayments(paymentClient);

        // make sure the payments have been reset

        for (uint i; i < recipients.length; ++i) {
            address recipient = recipients[i];

            assertEq(
                paymentProcessor.startForSpecificWalletId(
                    address(paymentClient), recipient, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.durationForSpecificWalletId(
                    address(paymentClient), recipient, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.releasedForSpecificWalletId(
                    address(paymentClient), recipient, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.vestedAmountForSpecificWalletId(
                    address(paymentClient), recipient, block.timestamp, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient), recipient, 1
                ),
                0
            );
        }
    }

    function testCancelPaymentsFailsWhenCalledByNonModule(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__OnlyCallableByModule
                    .selector
            )
        );
        paymentProcessor.cancelRunningPayments(paymentClient);
    }

    function testCancelPaymentsFailsWhenCalledOnOtherClient(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));

        PaymentClientMock otherPaymentClient = new PaymentClientMock(_token);

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.cancelRunningPayments(otherPaymentClient);
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
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF to half the max_duration
        vm.warp(max_duration / 2);

        // calling cancelRunningPayments also calls claim() so no need to repeat?
        vm.prank(address(paymentClient));
        paymentProcessor.cancelRunningPayments(paymentClient);

        // measure recipients balances before attempting second claim.
        uint[] memory balancesBefore = new uint256[](recipients.length);
        for (uint i; i < recipients.length; i++) {
            vm.prank(recipients[i]);
            balancesBefore[i] = _token.balanceOf(recipients[i]);
        }

        // skip to end of max_duration
        vm.warp(max_duration / 2);

        // make sure recipients cant claim 2nd time after cancelRunningPayments.
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];

            vm.startPrank(recipient);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ConcurrentStreamingPaymentProcessor
                        .Module__PaymentManager__NothingToClaim
                        .selector,
                    address(paymentClient),
                    recipient
                )
            );
            paymentProcessor.claimAll(paymentClient);
            vm.stopPrank();

            uint balanceAfter = _token.balanceOf(recipient);

            assertEq(balancesBefore[i], balanceAfter);
            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient), recipient, 1
                ),
                0
            );
        }
    }

    // Sanity Math Check
    function testStreamingCalculation(
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

        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint z = 0; z <= duration; z += 1 hours) {
            //we check each hour
            vm.warp(start + z);

            for (uint i = 0; i < recipients.length; i++) {
                address recipient = recipients[i];
                uint claimableAmt = amounts[i] * z / duration;

                assertEq(
                    claimableAmt,
                    paymentProcessor.releasableForSpecificWalletId(
                        address(paymentClient), recipient, 1
                    )
                );
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

        speedRunStreamingAndClaim(recipients, amounts, durations);

        vm.warp(block.timestamp + 52 weeks);

        speedRunStreamingAndClaim(recipients, amounts, durations);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]) * 2; //we paid two rounds

            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient), address(recipient), 1
                ),
                0
            );
        }

        // No funds left in the PaymentClient
        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }

    // Verifies our contract corectly handles ERC20 revertion.
    // 1. Recipient address is blacklisted on the ERC contract.
    // 2. Tries to claim tokens after 25% duration but ERC contract reverts.
    // 3. Recipient address is whitelisted in the ERC contract.
    // 4. Successfuly to claims tokens again after 50% duration.
    function testBlockedAddressCanClaimLater() public {
        address recipient = address(0xBABE);
        uint amount = 10 ether;
        uint duration = 10 days;

        // recipient is blacklisted.
        blockAddress(recipient);

        // Add payment order to client and call processPayments.
        paymentClient.addPaymentOrder(
            recipient, amount, (block.timestamp + duration)
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF 25% and claim.
        vm.warp(block.timestamp + duration / 4);
        vm.prank(recipient);
        paymentProcessor.claimAll(paymentClient);

        // after failed claim attempt receiver should receive 0 token,
        // while VPP should move recipient's balances from 'releasable' to 'unclaimable'
        assertEq(_token.balanceOf(address(recipient)), 0);
        assertEq(
            paymentProcessor.releasableForSpecificWalletId(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(address(paymentClient), recipient),
            amount / 4
        );

        // recipient is whitelisted.
        unblockAddress(recipient);

        // FF 25% and claim.
        vm.warp(block.timestamp + duration / 4);
        vm.prank(recipient);
        paymentProcessor.claimAll(paymentClient);

        // after successful claim attempt receiver should 50% total,
        // while both 'releasable' and 'unclaimable' recipient's amounts should be 0
        assertEq(_token.balanceOf(address(recipient)), amount / 2);
        assertEq(
            paymentProcessor.releasableForSpecificWalletId(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(address(paymentClient), recipient), 0
        );
    }

    // Verifies our contract corectly handles ERC20 retunrning false:
    // 1. Token address is broken and only returns false on failure
    // 2. Tries to claim tokens after 25% duration but ERC contract reverts.
    // 3. Token address is fixed works normally.
    // 4. Successfuly to claims tokens again after 50% duration.
    function testFalseReturningTokenTransfers() public {
        address recipient = address(0xBABE);
        uint amount = 10 ether;
        uint duration = 10 days;

        // Add payment order to client and call processPayments.
        paymentClient.addPaymentOrder(
            recipient, amount, (block.timestamp + duration)
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // FF 25% and claim.
        vm.warp(block.timestamp + duration / 4);
        vm.prank(recipient);
        paymentProcessor.claimAll(paymentClient);

        // after failed claim attempt receiver should receive 0 token,
        // while VPP should move recipient's balances from 'releasable' to 'unclaimable'
        assertEq(_token.balanceOf(address(recipient)), 0);
        assertEq(
            paymentProcessor.releasableForSpecificWalletId(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(address(paymentClient), recipient),
            amount / 4
        );

        // transfers will work normally again
        _token.toggleReturnFalse();

        // FF 25% and claim.
        vm.warp(block.timestamp + duration / 4);
        vm.prank(recipient);
        paymentProcessor.claimAll(paymentClient);

        // after successful claim attempt receiver should 50% total,
        // while both 'releasable' and 'unclaimable' recipient's amounts should be 0
        assertEq(_token.balanceOf(address(recipient)), amount / 2);
        assertEq(
            paymentProcessor.releasableForSpecificWalletId(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(address(paymentClient), recipient), 0
        );
    }

    //--------------------------------------------------------------------------
    // Helper functions

    // Speedruns a round of vesting + claiming
    // note Neither checks the inputs nor verifies results
    function speedRunStreamingAndClaim(
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
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        vm.warp(block.timestamp + max_time + 1);

        for (uint i; i < recipients.length; i++) {
            vm.prank(address(recipients[i]));
            paymentProcessor.claimAll(paymentClient);
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

    function assumeValidRecipient(address a) public view {
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
        pure
    {
        vm.assume(amounts.length != 0);
        for (uint i; i < checkUpTo; i++) {
            vm.assume(amounts[i] != 0);
        }
    }

    // note By only checking the values we'll use, we avoid unnecessary rejections
    function assumeValidDurations(uint64[] memory durations, uint checkUpTo)
        public
        pure
    {
        vm.assume(durations.length != 0);
        for (uint i; i < checkUpTo; i++) {
            vm.assume(durations[i] > 1);
        }
    }
}
