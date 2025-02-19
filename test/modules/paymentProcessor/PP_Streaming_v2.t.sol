// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// SuT
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

import {
    PP_Streaming_v2,
    IPP_Streaming_v2
} from "src/modules/paymentProcessor/PP_Streaming_v2.sol";

// Mocks

import {PP_Streaming_v2AccessMock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Streaming_v2AccessMock.sol";

import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_StreamingV1Test is ModuleTest {
    bytes32 internal constant _START_END_CLIFF_FLAG =
        0x000000000000000000000000000000000000000000000000000000000000000e;
    uint internal constant defaultStart = 69;
    uint internal constant defaultCliff = 13;
    uint internal constant defaultEnd = 420;

    // SuT
    PP_Streaming_v2AccessMock paymentProcessor;

    // Mocks
    ERC20PaymentClientBaseV2Mock paymentClient;

    //--------------------------------------------------------------------------
    // Events

    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        address indexed paymentToken,
        uint streamId,
        uint amount,
        uint start,
        uint cliff,
        uint end
    );
    event StreamingPaymentRemoved(
        address indexed paymentClient, address indexed recipient, uint streamId
    );
    event InvalidStreamingOrderDiscarded(
        address indexed recipient,
        address indexed paymentToken,
        uint amount,
        uint start,
        uint cliff,
        uint end
    );

    event UnclaimableAmountAdded(
        address indexed paymentClient,
        address recipient,
        address paymentToken,
        uint streamId,
        uint amount
    );

    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );

    event PaymentReceiverRemoved(
        address indexed paymentClient, address indexed paymentReceiver
    );

    function setUp() public {
        address impl = address(new PP_Streaming_v2AccessMock());
        paymentProcessor = PP_Streaming_v2AccessMock(Clones.clone(impl));

        _setUpOrchestrator(paymentProcessor);

        bytes memory configData =
            abi.encode(defaultStart, defaultCliff, defaultEnd);

        paymentProcessor.init(_orchestrator, _METADATA, configData);

        _authorizer.setIsAuthorized(address(this), true);

        // Set up PaymentClient Correctöy
        impl = address(new ERC20PaymentClientBaseV2Mock());
        paymentClient = ERC20PaymentClientBaseV2Mock(Clones.clone(impl));

        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));

        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    function testSupportsInterface() public {
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPP_Streaming_v2).interfaceId
            )
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, bytes(""));
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
            uint amount = amounts[i];
            uint time = durations[i];

            if (time > max_time) {
                max_time = time;
            }

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    amount,
                    block.timestamp,
                    0,
                    block.timestamp + durations[i]
                )
            );

            totalAmount += amount;
        }

        // Call processPayments.
        vm.prank(address(paymentClient));

        for (uint i; i < recipients.length; i++) {
            bytes32[] memory data = new bytes32[](3);
            data[0] = bytes32(block.timestamp);
            data[1] = bytes32(0);
            data[2] = bytes32(block.timestamp + durations[i]);

            vm.expectEmit(true, true, true, true);
            emit StreamingPaymentAdded(
                address(paymentClient),
                recipients[i],
                address(_token),
                1,
                amounts[i],
                block.timestamp,
                0,
                block.timestamp + durations[i]
            );
            emit IPaymentProcessor_v1.PaymentOrderProcessed(
                address(paymentClient),
                recipients[i],
                address(_token),
                amounts[i],
                block.chainid,
                block.chainid,
                _START_END_CLIFF_FLAG,
                data
            );
        }

        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < recipients.length;) {
            assertTrue(
                paymentProcessor.isActivePaymentReceiver(
                    address(paymentClient), recipients[i]
                )
            );
            assertEq(
                paymentProcessor.releasableForSpecificStream(
                    address(paymentClient),
                    recipients[i],
                    1 // 1 is the first default wallet ID for all unique recepients
                ),
                0,
                "Nothing would have vested at the start of the streaming duration"
            );
            unchecked {
                ++i;
            }
        }

        assertEq(totalAmount, _token.balanceOf(address(paymentClient)));
    }

    function test_claimStreamedAmounts_fullVesting(
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
            uint amount = uint(amounts[i]);
            uint time = uint(durations[i]);

            if (time > max_time) {
                max_time = time;
            }

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    amount,
                    block.timestamp,
                    0,
                    block.timestamp + time
                )
            );

            totalAmount += amount;
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < recipients.length;) {
            assertTrue(
                paymentProcessor.isActivePaymentReceiver(
                    address(paymentClient), recipients[i]
                )
            );
            assertEq(
                paymentProcessor.releasableForSpecificStream(
                    address(paymentClient),
                    recipients[i],
                    1 // 1 is the first default wallet ID for all unique recepients
                ),
                0,
                "Nothing would have vested at the start of the streaming duration"
            );
            unchecked {
                ++i;
            }
        }

        assertEq(totalAmount, _token.balanceOf(address(paymentClient)));

        // Moving ahead in time, past the longest streaming period
        vm.warp(block.timestamp + (max_time + 1));

        // All recepients try to claim their vested tokens
        for (uint i; i < recipients.length;) {
            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
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
                "Vested tokens not received by the paymentReceiver"
            );

            assertEq(
                paymentProcessor.releasableForSpecificStream(
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
        assertEq(totalAmount, paymentClient.amountPaidCounter(address(_token)));
    }

    // test cannot claim before cliff ends

    function test_claimStreamedAmounts_cannotClaimBeforeCliff(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= 10);
        vm.assume(recipients.length <= amounts.length);
        vm.assume(recipients.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);
        assumeValidDurations(durations, recipients.length);

        uint max_time = uint(durations[0]);
        uint totalAmount;

        for (uint i; i < recipients.length; i++) {
            durations[i] = uint64(bound(durations[i], 100, 100_000_000)); // by setting the minimum duration to 100, we ensure that the cliff period is always lower than the total duration
            uint amount = uint(amounts[i]);
            uint time = uint(durations[i]);

            if (time > max_time) {
                max_time = time;
            }

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    amount,
                    block.timestamp,
                    50,
                    block.timestamp + time
                )
            );

            totalAmount += amount;
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        assertEq(totalAmount, _token.balanceOf(address(paymentClient)));

        // Moving ahead in time, before the cliff period ends
        vm.warp(block.timestamp + 49);

        // All recepients try to claim their vested tokens
        for (uint i; i < recipients.length;) {
            uint balanceBefore = _token.balanceOf(recipients[i]);

            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
            assertTrue(
                paymentProcessor.isActivePaymentReceiver(
                    address(paymentClient), recipients[i]
                )
            );
            assertEq(
                paymentProcessor.releasableForSpecificStream(
                    address(paymentClient),
                    recipients[i],
                    1 // 1 is the first default wallet ID for all unique recepients
                ),
                0,
                "Nothing would have vested before the cliff period ends"
            );
            assertEq(_token.balanceOf(recipients[i]), balanceBefore);
            unchecked {
                ++i;
            }
        }

        // Now we move past the end of the longest streaming period
        vm.warp(block.timestamp + max_time);

        // All recepients try to claim their vested tokens
        for (uint i; i < recipients.length;) {
            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
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
                "Vested tokens not received by the paymentReceiver"
            );

            assertEq(
                paymentProcessor.releasableForSpecificStream(
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
        assertEq(totalAmount, paymentClient.amountPaidCounter(address(_token)));
    }

    function test_claimStreamedAmounts_CliffDoesNotInfluencePayout(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        vm.assume(recipients.length <= 10);
        vm.assume(recipients.length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, recipients.length);

        uint expectedHalfAmount;

        for (uint i; i < recipients.length; i++) {
            uint amount = uint(amounts[i]);

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    amount,
                    block.timestamp,
                    50_000,
                    block.timestamp + 100_000
                )
            );

            expectedHalfAmount += amount / 2;
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Moving ahead in time, before the cliff period ends
        vm.warp(block.timestamp + 49_999);

        // All recepients try to claim their vested tokens without success
        for (uint i; i < recipients.length;) {
            uint balanceBefore = _token.balanceOf(recipients[i]);
            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
            assertTrue(
                paymentProcessor.isActivePaymentReceiver(
                    address(paymentClient), recipients[i]
                )
            );
            assertEq(
                paymentProcessor.releasableForSpecificStream(
                    address(paymentClient),
                    recipients[i],
                    1 // 1 is the first default wallet ID for all unique recepients
                ),
                0,
                "Nothing would have vested before the cliff period ends"
            );
            assertEq(_token.balanceOf(recipients[i]), balanceBefore);
            unchecked {
                ++i;
            }
        }

        // Now we move to just the end of the cliff. Half of tokens should become unlocked
        vm.warp(block.timestamp + 1);

        // Now, all recipients should claim their entire vested amount
        for (uint i; i < recipients.length;) {
            uint balanceBefore = _token.balanceOf(recipients[i]);

            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
            // Check recipient balance
            assertEq(
                _token.balanceOf(recipients[i]),
                (uint(amounts[i]) / 2 + balanceBefore),
                "Vested tokens not received by the paymentReceiver"
            );
            assertEq(
                paymentProcessor.releasableForSpecificStream(
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
        assertEq(
            expectedHalfAmount, paymentClient.amountPaidCounter(address(_token))
        );
    }

    // @dev Assume recipient can withdraw full amount immediately if end is less than or equal to block.timestamp.
    function testProcessPaymentsWorksForEndTimeThatIsPlacedBeforeNow(
        address[] memory recipients,
        uint[] memory endTimes
    ) public {
        uint length = recipients.length;
        vm.assume(length < 50); // Restrict to reasonable size
        vm.assume(length <= endTimes.length);

        assumeValidRecipients(recipients);

        // Find the greatest timestamp in the array
        uint greatestEnd = 0;
        for (uint i; i < endTimes.length; i++) {
            if (endTimes[i] > greatestEnd) {
                greatestEnd = endTimes[i];
            }
        }

        // Warp to the greatest end value, so even that one is <= block.timestamp
        vm.warp(greatestEnd);

        // Amount of tokens for user that should be payed out
        uint payoutAmount = 100;

        for (uint i; i < length; i++) {
            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    payoutAmount,
                    0,
                    0,
                    endTimes[i]
                )
            );
        }

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        // Call processPayments
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < length; i++) {
            address recipient = recipients[i];
            IERC20PaymentClientBase_v2.PaymentOrder memory order = orders[i];

            uint end = uint(order.data[2]);

            // If end is before currentTimestamp evereything should be releasable
            if (end <= block.timestamp) {
                assertEq(
                    paymentProcessor.releasableForSpecificStream(
                        address(paymentClient), address(recipient), 1
                    ),
                    payoutAmount
                );

                vm.prank(recipient);
                paymentProcessor.claimAll(address(paymentClient));

                // Check correct balances.
                assertEq(_token.balanceOf(recipient), payoutAmount);
                assertEq(
                    paymentProcessor.releasableForSpecificStream(
                        address(paymentClient), recipient, 1
                    ),
                    0
                );
            }
        }
    }

    function test_processPayments_streamInfoGetsDeletedPostFullPayment(
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

        // We run process payments again, but since there are no new orders, nothing should happen.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];

            // Check that the stream information is deleted once vested tokens are claimed after total streaming duration
            assertEq(
                paymentProcessor.streamedAmountForSpecificStream(
                    address(paymentClient),
                    address(recipient),
                    1,
                    block.timestamp
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
        randomDuration = bound(randomDuration, 10, 100_000_000);
        randomAmount = bound(randomAmount, 10, 10_000);
        randomDuration_2 = bound(randomDuration_2, 1000, 100_000_000);
        randomAmount_2 = bound(randomAmount_2, 100, 10_000);

        address paymentReceiver1 = makeAddr("paymentReceiver1");
        address paymentReceiver2 = makeAddr("paymentReceiver2");
        address paymentReceiver3 = makeAddr("paymentReceiver3");
        address paymentReceiver4 = makeAddr("paymentReceiver4");

        address[3] memory paymentReceiverArray_1;
        paymentReceiverArray_1[0] = paymentReceiver1;
        paymentReceiverArray_1[1] = paymentReceiver2;
        paymentReceiverArray_1[2] = paymentReceiver3;

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
            address recipient = paymentReceiverArray_1[i];
            uint amount = amounts_1[i];
            uint time = durations_1[i];

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipient,
                    address(_token),
                    amount,
                    block.timestamp,
                    0,
                    block.timestamp + time
                )
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Let's travel in time, to the point after paymentReceiver1's tokens are fully vested.
        // Also, remember, nothing is claimed yet
        vm.warp(block.timestamp + durations_1[0]);

        // Now, the payment client decided to add a few more payment orders (with a few beneficiaries overlapping)
        address[3] memory paymentReceiverArray_2;
        paymentReceiverArray_2[0] = paymentReceiver2;
        paymentReceiverArray_2[1] = paymentReceiver3;
        paymentReceiverArray_2[2] = paymentReceiver4;

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
            address recipient = paymentReceiverArray_2[i];
            uint amount = amounts_2[i];
            uint time = durations_2[i];

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipient,
                    address(_token),
                    amount,
                    block.timestamp,
                    0,
                    block.timestamp + time
                )
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Now, let's check whether all streaming informations exist or not
        // checking for paymentReceiver2
        IPP_Streaming_v2.Stream[] memory paymentReceiverStreams;
        paymentReceiverStreams = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver2
        );

        assertTrue(paymentReceiverStreams.length == 2);
        assertEq(
            (
                paymentReceiverStreams[0]._total
                    + paymentReceiverStreams[1]._total
            ),
            (amounts_1[1] + amounts_2[0]),
            "Improper accounting of orders"
        );

        // checking for paymentReceiver3
        paymentReceiverStreams = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver3
        );

        assertTrue(paymentReceiverStreams.length == 2);
        assertEq(
            (
                paymentReceiverStreams[0]._total
                    + paymentReceiverStreams[1]._total
            ),
            (amounts_1[2] + amounts_2[1]),
            "Improper accounting of orders"
        );

        // checking for paymentReceiver 4
        paymentReceiverStreams = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver4
        );

        assertTrue(paymentReceiverStreams.length == 1);
        assertEq(
            (paymentReceiverStreams[0]._total),
            (amounts_2[2]),
            "Improper accounting of orders"
        );

        // checking for paymentReceiver 1
        paymentReceiverStreams = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        assertTrue(paymentReceiverStreams.length == 1);
        assertEq(
            (paymentReceiverStreams[0]._total),
            (amounts_1[0]),
            "Improper accounting of orders"
        );
    }

    uint initialNumWallets;
    uint initialPaymentReceiverBalance;
    uint initialStreamIdAtIndex1;
    uint finalNumWallets;
    uint finalPaymentReceiverBalance;

    function test_removePaymentForSpecificStream_halfVestingDoneMultipleOrdersForSingleBeneficiary(
        uint randomDuration,
        uint randomAmount,
        uint randomDuration_2,
        uint randomAmount_2
    ) public {
        randomDuration = bound(randomDuration, 10, 100_000_000);
        randomAmount = bound(randomAmount, 10, 10_000);
        randomDuration_2 = bound(randomDuration_2, 1000, 100_000_000);
        randomAmount_2 = bound(randomAmount_2, 100, 10_000);

        address paymentReceiver1 = makeAddr("paymentReceiver1");
        address paymentReceiver2 = makeAddr("paymentReceiver2");
        address paymentReceiver3 = makeAddr("paymentReceiver3");
        address paymentReceiver4 = makeAddr("paymentReceiver4");

        address[6] memory paymentReceiverArray;
        paymentReceiverArray[0] = paymentReceiver1;
        paymentReceiverArray[1] = paymentReceiver2;
        paymentReceiverArray[2] = paymentReceiver3;
        paymentReceiverArray[3] = paymentReceiver1;
        paymentReceiverArray[4] = paymentReceiver4;
        paymentReceiverArray[5] = paymentReceiver1;

        uint[6] memory durations;
        for (uint i; i < 6; i++) {
            durations[i] = (randomDuration * (i + 1));
        }

        uint[6] memory amounts;
        for (uint i; i < 6; i++) {
            amounts[i] = (randomAmount * (i + 1));
        }

        // Add these payment orders to the payment client
        for (uint i; i < 6; i++) {
            address recipient = paymentReceiverArray[i];
            uint amount = amounts[i];
            uint time = durations[i];

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipient,
                    address(_token),
                    amount,
                    block.timestamp,
                    0,
                    block.timestamp + time
                )
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Let's travel in time, to the point after paymentReceiver1's tokens for the second payment order
        // are 1/2 vested.
        vm.warp(block.timestamp + (durations[3] / 2));

        // This means, that when we call removePaymentForSpecificStream, that should increase the balance of the
        // paymentReceiver by 1/2 of the vested token amount
        IPP_Streaming_v2.Stream[] memory paymentReceiverStreams =
        paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        // We are interested in finding the details of the 2nd wallet of paymentReceiver1
        uint expectedTotal = paymentReceiverStreams[1]._total;
        uint walletId = paymentReceiverStreams[1]._streamId;

        initialNumWallets = paymentReceiverStreams.length;
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);
        initialStreamIdAtIndex1 = walletId;

        assertTrue(expectedTotal != 0);

        vm.prank(address(this)); // stupid line, ik, but it's just here to show that onlyOrchestratorAdmin can call the next function
        paymentProcessor.removePaymentForSpecificStream(
            address(paymentClient), paymentReceiver1, walletId
        );

        paymentReceiverStreams = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        finalNumWallets = paymentReceiverStreams.length;
        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(finalNumWallets + 1, initialNumWallets);
        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            (expectedTotal / 2)
        );
        // Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(
            paymentClient.amountPaidCounter(address(_token)), expectedTotal
        );
        assertTrue(
            initialStreamIdAtIndex1 != paymentReceiverStreams[1]._streamId
        );
    }

    uint total1;
    uint total2;
    uint total3;
    uint amountPaidAlready;

    function test_removePaymentAndClaimForSpecificStream(
        uint randomDuration,
        uint randomAmount,
        uint randomDuration_2,
        uint randomAmount_2
    ) public {
        randomDuration = bound(randomDuration, 10, 100_000_000);
        randomAmount = bound(randomAmount, 10, 10_000);
        randomDuration_2 = bound(randomDuration_2, 1000, 100_000_000);
        randomAmount_2 = bound(randomAmount_2, 100, 10_000);

        address paymentReceiver1 = makeAddr("paymentReceiver1");
        address paymentReceiver2 = makeAddr("paymentReceiver2");
        address paymentReceiver3 = makeAddr("paymentReceiver3");
        address paymentReceiver4 = makeAddr("paymentReceiver4");

        address[6] memory paymentReceiverArray;
        paymentReceiverArray[0] = paymentReceiver1;
        paymentReceiverArray[1] = paymentReceiver2;
        paymentReceiverArray[2] = paymentReceiver3;
        paymentReceiverArray[3] = paymentReceiver1;
        paymentReceiverArray[4] = paymentReceiver4;
        paymentReceiverArray[5] = paymentReceiver1;

        uint[6] memory durations;
        for (uint i; i < 6; i++) {
            durations[i] = (randomDuration * (i + 1));
        }

        // we want the durations of the stream for paymentReceiver 1 to be double of the initial one
        // and the last payment order to have the same duration as the middle one
        durations[3] = durations[0] * 2;
        durations[5] = durations[3];

        uint[6] memory amounts;
        for (uint i; i < 6; i++) {
            amounts[i] = (randomAmount * (i + 1));
        }

        // Add these payment orders to the payment client
        for (uint i; i < 6; i++) {
            address recipient = paymentReceiverArray[i];
            uint amount = amounts[i];
            uint time = durations[i];

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipient,
                    address(_token),
                    amount,
                    block.timestamp,
                    0,
                    block.timestamp + time
                )
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Let's travel in time, to the point after paymentReceiver1's tokens for the second payment order
        // are 1/2 vested, or the complete streaming of duration of the first payment order
        vm.warp(block.timestamp + durations[0]);

        // Let's note down the current balance of the paymentReceiver1
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        IPP_Streaming_v2.Stream[] memory paymentReceiverStreams =
        paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        total1 = paymentReceiverStreams[0]._total;

        // Now we claim the entire total amount from the first payment order
        vm.prank(paymentReceiver1);
        paymentProcessor.claimForSpecificStream(
            address(paymentClient), paymentReceiverStreams[0]._streamId
        );

        // Now we note down the balance of the paymentReceiver1 again after claiming for the first wallet.
        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            total1
        );

        // Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(paymentClient.amountPaidCounter(address(_token)), total1);
        amountPaidAlready += paymentClient.amountPaidCounter(address(_token));

        // Now we are interested in finding the details of the 2nd wallet of paymentReceiver1
        total2 = (paymentReceiverStreams[1]._total) / 2; // since we are at half the streaming duration
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertTrue(total2 != 0);

        vm.prank(address(this)); // stupid line, ik, but it's just here to show that onlyOrchestratorAdmin can call the next function
        paymentProcessor.removePaymentForSpecificStream(
            address(paymentClient),
            paymentReceiver1,
            paymentReceiverStreams[1]._streamId
        );

        // Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(
            paymentClient.amountPaidCounter(address(_token)),
            paymentReceiverStreams[1]._total + total1
        );
        amountPaidAlready = paymentClient.amountPaidCounter(address(_token));

        paymentReceiverStreams = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        finalNumWallets = paymentReceiverStreams.length;
        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(finalNumWallets, 1); // One was deleted because the streaming was completed and claimed. The other was deleted because of removePayment
        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            total2
        );

        // Now we try and claim the 3rd payment order for paymentReceiver1
        // we are at half it's streaming period, so the total3 should be half of the total amount
        // The third wallet is at the 0th index now, since the other 2 have been deleted due to removal and complete streaming.
        total3 = (paymentReceiverStreams[0]._total) / 2;
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        vm.prank(paymentReceiver1);
        paymentProcessor.claimForSpecificStream(
            address(paymentClient), paymentReceiverStreams[0]._streamId
        );
        // Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(
            paymentClient.amountPaidCounter(address(_token)) - amountPaidAlready,
            total3
        );

        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            total3
        );
    }

    function test_processPayments_failsWhenCalledByNonModule(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_authorizer));
        vm.assume(nonModule != address(_fundingManager));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__OnlyCallableByModule
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
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        ERC20PaymentClientBaseV2Mock otherERC20PaymentClient =
            new ERC20PaymentClientBaseV2Mock();

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.processPayments(otherERC20PaymentClient);
    }

    function test_processPayments_FailsIfPaymentOrderRecipientIsInvalid()
        public
    {
        // Values to use for testing.
        address recipient = address(paymentClient); // Wrong Value
        address paymentToken = address(_token);
        uint amount = 1e18;
        uint start = block.timestamp;
        uint cliff = 100;
        uint end = block.timestamp + 200;

        // Add payment order to client.
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient, paymentToken, amount, start, cliff, end
            )
        );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                    .selector
            )
        );

        paymentProcessor.processPayments(paymentClient);
    }

    function test_processPayments_FailsIfPaymentOrderTokenIsInvalid() public {
        // Values to use for testing.
        address recipient = address(0x1234);
        address paymentToken = address(paymentClient); // Wrong Value
        uint amount = 1e18;
        uint start = block.timestamp;
        uint cliff = 100;
        uint end = block.timestamp + 200;

        // Add payment order to client.
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient, paymentToken, amount, start, cliff, end
            )
        );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            // The call to check if it's an ERC20 reverts
        );

        paymentProcessor.processPayments(paymentClient);
    }

    function test_processPayments_FailsIfPaymentOrderAmountsInvalid() public {
        // Values to use for testing.
        address recipient = address(0x1234);
        address paymentToken = address(_token);
        uint amount = 0; // Wrong value
        uint start = block.timestamp;
        uint cliff = 100;
        uint end = block.timestamp + 200;

        // Add payment order to client.
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient, paymentToken, amount, start, cliff, end
            )
        );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                    .selector
            )
        );

        paymentProcessor.processPayments(paymentClient);
    }

    function test_processPayments_FailsIfPaymentOrderStartIsInvalid() public {
        // Values to use for testing.
        address recipient = address(0x1234);
        address paymentToken = address(_token);
        uint amount = 1e18;
        uint start = block.timestamp + 300; // Wrong Value
        uint cliff = 100;
        uint end = block.timestamp + 200;

        // Add payment order to client.
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient, paymentToken, amount, start, cliff, end
            )
        );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                    .selector
            )
        );

        paymentProcessor.processPayments(paymentClient);
    }

    function test_processPayments_FailsIfPaymentOrderCliffIsInvalid() public {
        // Values to use for testing.
        address recipient = address(0x1234);
        address paymentToken = address(_token);
        uint amount = 1e18;
        uint start = block.timestamp;
        uint cliff = 300; // Wrong Value
        uint end = block.timestamp + 200;

        // Add payment order to client.
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient, paymentToken, amount, start, cliff, end
            )
        );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                    .selector
            )
        );

        paymentProcessor.processPayments(paymentClient);
    }

    function test_processPayments_FailsIfPaymentOrderEndIsInvalid() public {
        // Values to use for testing.
        address recipient = address(0x1234);
        address paymentToken = address(_token);
        uint amount = 1e18;
        uint start = block.timestamp;
        uint cliff = 100;
        uint end = block.timestamp - 100; // Wrong Value

        // Add payment order to client.
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient, paymentToken, amount, start, cliff, end
            )
        );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                    .selector
            )
        );

        paymentProcessor.processPayments(paymentClient);
    }

    function test_cancelRunningPayments_allCreatedOrdersGetCancelled(
        address[] memory recipients,
        uint128[] memory amounts
    ) public {
        uint length = recipients.length;
        vm.assume(length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, length);

        uint duration = 4 weeks;

        for (uint i = 0; i < length; ++i) {
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    amounts[i],
                    block.timestamp,
                    0,
                    block.timestamp + duration
                )
            );
        }
        // Expect the correct number and sequence of emits
        for (uint i = 0; i < length; ++i) {
            bytes32[] memory data = new bytes32[](3);
            data[0] = bytes32(block.timestamp);
            data[1] = bytes32(0);
            data[2] = bytes32(duration + block.timestamp);

            vm.expectEmit(true, true, true, true);
            emit StreamingPaymentAdded(
                address(paymentClient),
                recipients[i],
                address(_token),
                1,
                amounts[i],
                block.timestamp,
                0,
                duration + block.timestamp
            );
            emit IPaymentProcessor_v1.PaymentOrderProcessed(
                address(paymentClient),
                recipients[i],
                address(_token),
                amounts[i],
                block.chainid,
                block.chainid,
                _START_END_CLIFF_FLAG,
                data
            );
        }

        // Call processPayments and expect emits
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF to half the max_duration
        vm.warp(block.timestamp + 2 weeks);

        // we expect cancellation events for each payment
        for (uint i = 0; i < length; ++i) {
            vm.expectEmit(true, true, true, true);
            // we can expect all recipient to be unique due to the call to assumeValidRecipients.
            // Therefore, the walletId of all these paymentReceivers would be 1.
            emit StreamingPaymentRemoved(
                address(paymentClient), recipients[i], 1
            );
        }

        // calling cancelRunningPayments
        vm.prank(address(paymentClient));
        paymentProcessor.cancelRunningPayments(paymentClient);

        // make sure the payments have been reset

        for (uint i; i < length; ++i) {
            address recipient = recipients[i];

            assertEq(
                paymentProcessor.startForSpecificStream(
                    address(paymentClient), recipient, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.endForSpecificStream(
                    address(paymentClient), recipient, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.releasedForSpecificStream(
                    address(paymentClient), recipient, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.streamedAmountForSpecificStream(
                    address(paymentClient), recipient, 1, block.timestamp
                ),
                0
            );
            assertEq(
                paymentProcessor.releasableForSpecificStream(
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
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__OnlyCallableByModule
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
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        ERC20PaymentClientBaseV2Mock otherERC20PaymentClient =
            new ERC20PaymentClientBaseV2Mock();

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.cancelRunningPayments(otherERC20PaymentClient);
    }

    // This test creates a new set of payments in a client which finished all running payments.
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
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipient,
                    address(_token),
                    amounts[i],
                    block.timestamp,
                    0,
                    block.timestamp + durations[i]
                )
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF to half the max_duration
        vm.warp(max_duration / 2);

        // calling cancelRunningPayments also calls claim() so no need to repeat?
        vm.prank(address(paymentClient));
        vm.expectEmit(true, true, true, true);
        emit PaymentReceiverRemoved(address(paymentClient), recipients[0]);
        paymentProcessor.cancelRunningPayments(paymentClient);

        // measure recipients balances before attempting second claim.
        uint[] memory balancesBefore = new uint[](recipients.length);
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
                    IPaymentProcessor_v1
                        .Module__PaymentProcessor__NothingToClaim
                        .selector,
                    address(paymentClient),
                    recipient
                )
            );
            paymentProcessor.claimAll(address(paymentClient));
            vm.stopPrank();

            uint balanceAfter = _token.balanceOf(recipient);

            assertEq(balancesBefore[i], balanceAfter);
            assertEq(
                paymentProcessor.releasableForSpecificStream(
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
        uint length = recipients.length;
        vm.assume(length < 50); // Reasonable amount
        vm.assume(length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, length);

        uint start = block.timestamp;
        uint duration = 1 weeks;

        for (uint i = 0; i < length; i++) {
            address recipient = recipients[i];
            uint amount = amounts[i];

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipient,
                    address(_token),
                    amount,
                    block.timestamp,
                    0,
                    block.timestamp + duration
                )
            );
        }

        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint z = 0; z <= duration; z += 1 hours) {
            // we check each hour
            vm.warp(start + z);

            for (uint i = 0; i < recipients.length; i++) {
                address recipient = recipients[i];
                uint claimableAmt = amounts[i] * z / duration;

                assertEq(
                    claimableAmt,
                    paymentProcessor.releasableForSpecificStream(
                        address(paymentClient), recipient, 1
                    )
                );
            }
        }
    }

    function testClaimPreviouslyUnclaimable(address[] memory recipients)
        public
    {
        vm.assume(recipients.length < 30);

        for (uint i = 0; i < recipients.length; i++) {
            // If recipient is invalid change it
            if (recipients[i] == address(0) || recipients[i].code.length != 0) {
                recipients[i] = address(0x1);
            }
        }

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // Add payment order to client and call processPayments.

        for (uint i = 0; i < recipients.length; i++) {
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    1,
                    block.timestamp,
                    0,
                    block.timestamp
                )
            );
            vm.prank(address(paymentClient));
            paymentProcessor.processPayments(paymentClient);

            // Immediately claim
            // This should shift right into unclaimable
            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
        }

        // transfers will not fail anymore
        _token.toggleReturnFalse();

        uint amount;
        address recipient;
        uint amountPaid;
        for (uint i = 0; i < recipients.length; i++) {
            recipient = recipients[i];

            // Check that recipients are not handled twice
            if (recipientsHandled[recipient]) continue;
            recipientsHandled[recipient] = true;

            amount = paymentProcessor.unclaimable(
                address(paymentClient), address(_token), recipient
            );

            // Grab Unclaimable Wallet Ids array
            uint[] memory ids = paymentProcessor.getUnclaimableStreams(
                address(paymentClient), address(_token), recipient
            );

            // Do call
            vm.expectEmit(true, true, true, true);
            emit TokensReleased(recipient, address(_token), amount);

            vm.prank(recipient);
            paymentProcessor.claimPreviouslyUnclaimable(
                address(paymentClient), address(_token), recipient
            );

            // Unclaimable amount for Wallet Ids empty (mapping)
            for (uint j = 0; j < ids.length; j++) {
                assertEq(
                    paymentProcessor.getUnclaimableAmountForStreams(
                        address(paymentClient),
                        address(_token),
                        recipient,
                        ids[j]
                    ),
                    0
                );
            }

            // Check Unclaimable Wallet Ids array empty
            assertEq(
                paymentProcessor.getUnclaimableStreams(
                    address(paymentClient), address(_token), recipient
                ).length,
                0
            );

            // Amount send
            assertEq(_token.balanceOf(recipient), amount);

            // Check that amountPaid is correct in PaymentClient
            amountPaid += amount;
            assertEq(
                paymentClient.amountPaidCounter(address(_token)), amountPaid
            );
        }
    }

    mapping(address => bool) recipientsHandled;

    function testClaimPreviouslyUnclaimableFailsIfNothingToClaim() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__NothingToClaim
                    .selector,
                address(paymentClient),
                address(this)
            )
        );
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), address(0), address(0x1)
        );
    }

    // This test creates a new set of payments in a client which finished all running payments.
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
        address recipient;
        uint amount;
        uint totalAmount;
        for (uint i; i < recipients.length; i++) {
            recipient = recipients[i];
            amount = uint(amounts[i]) * 2; // we paid two rounds
            totalAmount += amount;

            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(
                paymentProcessor.releasableForSpecificStream(
                    address(paymentClient), address(recipient), 1
                ),
                0
            );
            assertEq(
                paymentProcessor.releasableForSpecificStream(
                    address(paymentClient), address(recipient), 2
                ),
                0
            );
        }

        // No funds left in the ERC20PaymentClientBase_v2
        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);

        assertEq(totalAmount, paymentClient.amountPaidCounter(address(_token)));
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
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient,
                address(_token),
                amount,
                block.timestamp,
                0,
                block.timestamp + duration
            )
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF 25% and claim.
        vm.warp(block.timestamp + duration / 4);

        vm.expectEmit(true, true, true, true);
        emit UnclaimableAmountAdded(
            address(paymentClient), recipient, address(_token), 1, amount / 4
        );

        vm.prank(recipient);
        paymentProcessor.claimAll(address(paymentClient));

        // after failed claim attempt receiver should receive 0 token,
        // while VPP should move recipient's balances from 'releasable' to 'unclaimable'
        assertEq(_token.balanceOf(address(recipient)), 0);
        assertEq(
            paymentProcessor.releasableForSpecificStream(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), recipient
            ),
            amount / 4
        );

        // recipient is whitelisted.
        unblockAddress(recipient);

        // claim the previously unclaimable amount
        vm.prank(recipient);
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), recipient
        );

        // after successful claim of the previously unclaimable amount the receiver should have 25% total,
        // while both 'releasable' and 'unclaimable' recipient's amounts should be 0
        assertEq(_token.balanceOf(address(recipient)), amount / 4);
        assertEq(
            paymentProcessor.releasableForSpecificStream(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), recipient
            ),
            0
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
        paymentClient.exposed_addPaymentOrder(
            createPaymentOrder(
                recipient,
                address(_token),
                amount,
                block.timestamp,
                0,
                block.timestamp + duration
            )
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // FF 25% and claim.
        vm.warp(block.timestamp + duration / 4);
        vm.prank(recipient);
        paymentProcessor.claimAll(address(paymentClient));

        // after failed claim attempt receiver should receive 0 token,
        // while VPP should move recipient's balances from 'releasable' to 'unclaimable'
        assertEq(_token.balanceOf(address(recipient)), 0);
        assertEq(
            paymentProcessor.releasableForSpecificStream(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), recipient
            ),
            amount / 4
        );

        // transfers will work normally again
        _token.toggleReturnFalse();

        // claim the previously unclaimable amount
        vm.prank(recipient);
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), recipient
        );

        // after successful claim of the previously unclaimable amount the receiver should have 25% total,
        // while both 'releasable' and 'unclaimable' recipient's amounts should be 0
        assertEq(_token.balanceOf(address(recipient)), amount / 4);
        assertEq(
            paymentProcessor.releasableForSpecificStream(
                address(paymentClient), recipient, 1
            ),
            0
        );
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), recipient
            ),
            0
        );
    }

    function testUnclaimable(address[] memory recipients) public {
        vm.assume(recipients.length < 30);

        for (uint i = 0; i < recipients.length; i++) {
            // If recipient is invalid change it
            if (recipients[i] == address(0) || recipients[i].code.length != 0) {
                recipients[i] = address(0x1);
            }
        }

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // Add payment order to client and call processPayments.

        for (uint i = 0; i < recipients.length; i++) {
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    1,
                    block.timestamp,
                    0,
                    block.timestamp
                )
            );
            vm.prank(address(paymentClient));
            paymentProcessor.processPayments(paymentClient);

            // Immediately claim
            // This should shift right into unclaimable
            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
        }

        uint amount;
        address recipient;
        for (uint i = 0; i < recipients.length; i++) {
            amount = 0;
            recipient = recipients[i];
            // if array contains address multiple times we check for repetitions
            for (uint j = 0; j < recipients.length; j++) {
                if (recipients[j] == recipient) {
                    amount += 1;
                }
            }
            assertEq(
                paymentProcessor.unclaimable(
                    address(paymentClient), address(_token), recipient
                ),
                amount
            );
        }
    }

    function testTimeVerificationIsCorrectlyImplemented(
        uint start,
        uint cliff,
        uint end
    ) public {
        // check if an overflow will happen via unchecked
        bool willRevert = false;
        unchecked {
            if (start + cliff < start) {
                willRevert = true;
            }
        }
        vm.assume(!willRevert);

        // Specifically test each aspect of the time verification here as well
        // to find out whether it should revert or not
        bool resultShouldBe = true;

        // Check whether the start is greater than the end time
        // Them being equal is fine if no streaming is desired (instant payout)
        if (start > end) {
            resultShouldBe = false;
        }

        // Check whether the start with cliff added is greater than the end time
        // Them being equal is fine again, as that would just be a delayed full payout
        // (if cliff > 0)
        if (start + cliff > end) {
            resultShouldBe = false;
        }

        bool result = paymentProcessor.exposed_validTimes(start, cliff, end);
        assertEq(result, resultShouldBe);
    }

    function test_ValidPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        address sender,
        uint start,
        uint cliff,
        uint end
    ) public {
        // The randomToken can't be the address of the Create2Deployer
        // as that one uses a fallback function to deploy contracts, it will
        // pass the test here
        vm.assume(
            order.paymentToken != 0x4e59b44847b379578588920cA78FbF26c0B4956C
        );

        start = bound(start, 0, type(uint).max / 2);
        cliff = bound(cliff, 0, type(uint).max / 2);
        end = bound(end, 0, type(uint).max / 2);

        bytes32[] memory data = new bytes32[](3);
        data[0] = bytes32(start);
        data[1] = bytes32(cliff);
        data[2] = bytes32(end);

        // Set up data array before accessing it
        order.data = data;

        // Set flags to indicate all values are present
        order.flags = bytes32(uint(7)); // 7 = 0b111 to set first 3 bits

        vm.startPrank(sender);

        bool expectedValue = paymentProcessor.exposed_validPaymentReceiver(
            order.recipient
        ) && paymentProcessor.exposed_validPaymentToken(order.paymentToken)
            && paymentProcessor.exposed_validTimes(
                uint(order.data[0]), uint(order.data[1]), uint(order.data[2])
            ) && paymentProcessor.exposed__validTotal(order.amount);

        assertEq(paymentProcessor.validPaymentOrder(order), expectedValue);

        vm.stopPrank();
    }

    function test__validPaymentReceiver(address addr, address sender) public {
        bool expectedValue = true;
        if (
            addr == address(0) || addr == sender
                || addr == address(paymentProcessor)
                || addr == address(_orchestrator)
                || addr == address(_orchestrator.fundingManager().token())
        ) {
            expectedValue = false;
        }

        vm.prank(sender);

        assertEq(
            paymentProcessor.exposed_validPaymentReceiver(addr), expectedValue
        );
    }

    function test__validTotal(uint _total) public {
        bool expectedValue = true;
        if (_total == 0) {
            expectedValue = false;
        }

        assertEq(paymentProcessor.exposed__validTotal(_total), expectedValue);
    }

    function test__validTimes(uint _start, uint _cliff, uint _end) public {
        _start = bound(_start, 0, type(uint).max / 2);
        _cliff = bound(_cliff, 0, type(uint).max / 2);

        bool expectedValue = true;
        if (_start + _cliff > _end) {
            expectedValue = false;
        }

        assertEq(
            paymentProcessor.exposed_validTimes(_start, _cliff, _end),
            expectedValue
        );
    }

    function test__validPaymentToken(address randomToken, address sender)
        public
    {
        // Non-contract addresses or protected addresses should be invalid
        vm.assume(randomToken != address(_token));

        // The randomToken can't be the address of the Create2Deployer
        // as that one uses a fallback funciton to deploy contracts, it will
        // pass the test here
        vm.assume(randomToken != 0x4e59b44847b379578588920cA78FbF26c0B4956C);

        vm.prank(sender);

        assertEq(paymentProcessor.exposed_validPaymentToken(randomToken), false);

        // ERC20 addresses are valid
        ERC20Mock actualToken = new ERC20Mock("Test", "TST");

        vm.prank(sender);
        assertEq(
            paymentProcessor.exposed_validPaymentToken(address(actualToken)),
            true
        );

        vm.prank(sender);
        assertEq(
            paymentProcessor.exposed_validPaymentToken(address(_token)), true
        );
    }

    function test__getStreamingDetails(bytes32 flags, bytes32[] memory data)
        public
    {
        // the P_P doesn't use this, but it could be part of recieved data
        bool hasOrderId = false;
        bool hasStart = false;
        bool hasCliff = false;
        bool hasEnd = false;

        uint8 numOnes = 0;
        if ((uint(flags) & (1 << 0)) != 0) {
            hasOrderId = true;
            numOnes++;
        }
        if ((uint(flags) & (1 << 1)) != 0) {
            hasStart = true;
            numOnes++;
        }
        if ((uint(flags) & (1 << 2)) != 0) {
            hasCliff = true;
            numOnes++;
        }
        if ((uint(flags) & (1 << 3)) != 0) {
            hasEnd = true;
            numOnes++;
        }

        // Bound data length to match number of flags set
        vm.assume(data.length >= numOnes);
        if (data.length > numOnes) {
            bytes32[] memory newData = new bytes32[](numOnes);
            for (uint i = 0; i < numOnes; i++) {
                newData[i] = data[i];
            }
            data = newData;
        }

        (uint start, uint cliff, uint end) =
            paymentProcessor.exposed_getStreamingDetails(flags, data);

        uint idx = 0;
        // if there was an orderId, start comparing results one index further
        if (hasOrderId) idx++;
        assertEq(start, hasStart ? uint(data[idx]) : defaultStart);
        if (hasStart) idx++;
        assertEq(cliff, hasCliff ? uint(data[idx]) : defaultCliff);
        if (hasCliff) idx++;
        assertEq(end, hasEnd ? uint(data[idx]) : defaultEnd);
    }

    function test_setStreamingDefaults(
        uint defaultStart,
        uint defaultCliff,
        uint defaultEnd
    ) public {
        defaultStart = bound(defaultStart, 0, defaultEnd);
        defaultCliff = bound(defaultCliff, 0, defaultEnd - defaultStart);

        // Set default times
        paymentProcessor.setStreamingDefaults(
            defaultStart, defaultCliff, defaultEnd
        );
        // Check default times
        (uint start, uint cliff, uint end) =
            paymentProcessor.getStreamingDefaults();
        assertEq(start, defaultStart);
        assertEq(cliff, defaultCliff);
        assertEq(end, defaultEnd);
    }

    function test_setStreamingDefaults_FailsIfInvalidTimes(
        uint defaultStart,
        uint defaultCliff,
        uint defaultEnd
    ) public {
        vm.assume(defaultStart < 1e24); //upper bounds to avoid overflow
        vm.assume(defaultCliff < 1e24);
        vm.assume(defaultStart + defaultCliff != 0);

        defaultEnd = bound(defaultEnd, 0, (defaultStart + defaultCliff - 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPP_Streaming_v2
                    .Module__PP_Streaming__InvalidDefaultTimes
                    .selector,
                defaultStart,
                defaultCliff,
                defaultEnd
            )
        );
        paymentProcessor.setStreamingDefaults(
            defaultStart, defaultCliff, defaultEnd
        );
    }

    function test_getProcessorFlags() public {
        bytes32 flags = paymentProcessor.getProcessorFlags();
        assertEq(flags, _START_END_CLIFF_FLAG);
    }

    //--------------------------------------------------------------------------
    // Helper functions

    // Speedruns a round of streaming + claiming
    // note Neither checks the inputs nor verifies results
    function speedRunStreamingAndClaim(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory ends
    ) internal {
        uint max_time = ends[0];

        for (uint i; i < recipients.length; i++) {
            uint time = ends[i];

            if (time > max_time) {
                max_time = time;
            }

            // Add payment order to client.
            paymentClient.exposed_addPaymentOrder(
                createPaymentOrder(
                    recipients[i],
                    address(_token),
                    amounts[i],
                    block.timestamp,
                    0,
                    block.timestamp + time
                )
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        vm.warp(block.timestamp + max_time + 1);

        for (uint i; i < recipients.length; i++) {
            vm.prank(address(recipients[i]));
            paymentProcessor.claimAll(address(paymentClient));
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

    function createPaymentOrder(
        address recipient,
        address paymentToken,
        uint amount,
        uint start,
        uint cliff,
        uint end
    )
        internal
        view
        returns (IERC20PaymentClientBase_v2.PaymentOrder memory paymentOrder)
    {
        bytes32 flagsBytes =
            0x000000000000000000000000000000000000000000000000000000000000000e;
        bytes32[] memory data = new bytes32[](3);
        data[0] = bytes32(start);
        data[1] = bytes32(cliff);
        data[2] = bytes32(end);

        paymentOrder = IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient,
            paymentToken: paymentToken,
            amount: amount,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flagsBytes,
            data: data
        });
    }

    //--------------------------------------------------------------------------
    // Fuzzing Validation Helpers

    mapping(address => bool) recipientCache;

    function assumeValidRecipients(address[] memory addrs) public {
        vm.assume(addrs.length != 0);
        for (uint i; i < addrs.length; i++) {
            assumeValidRecipient(addrs[i]);

            // Assume paymentReceiver address unique.
            vm.assume(!recipientCache[addrs[i]]);

            // Add paymentReceiver address to cache.
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
        invalids[1] = address(_orchestrator);
        invalids[2] = address(paymentProcessor);
        invalids[3] = address(paymentClient);
        invalids[4] = address(_token);

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
