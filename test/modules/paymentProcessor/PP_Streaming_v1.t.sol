// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";
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
    PP_Streaming_v1,
    IPP_Streaming_v1
} from "src/modules/paymentProcessor/PP_Streaming_v1.sol";

// Mocks

import {PP_Streaming_v1AccessMock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Streaming_v1AccessMock.sol";

import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_StreamingV1Test is //@note do we want to do anything about these tests?
    ModuleTest {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // SuT
    PP_Streaming_v1AccessMock paymentProcessor;

    // Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param dueTo Timestamp at which the full amount should be claimable.
    /// @param walletId ID of the payment order that was added
    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint dueTo,
        uint walletId
    );

    /// @notice Emitted when the vesting to an address is removed.
    /// @param recipient The address that will stop receiving payment.
    /// @param walletId ID of the payment order removed
    event StreamingPaymentRemoved(
        address indexed paymentClient,
        address indexed recipient,
        uint indexed walletId
    );

    /// @notice Emitted when a running vesting schedule gets updated.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param dueTo Timestamp at which the full amount should be claimable.
    event InvalidStreamingOrderDiscarded(
        address indexed recipient, uint amount, uint start, uint dueTo
    );

    /// @notice Emitted when a payment gets processed for execution.
    /// @param paymentClient The payment client that originated the order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param createdAt Timestamp at which the order was created.
    /// @param dueTo Timestamp at which the full amount should be payed out/claimable.
    /// @param walletId ID of the payment order that was processed
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint createdAt,
        uint dueTo,
        uint walletId
    );

    event UnclaimableAmountAdded(
        address indexed paymentClient,
        address recipient,
        uint walletId,
        uint amount
    );

    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );

    function setUp() public {
        address impl = address(new PP_Streaming_v1AccessMock());
        paymentProcessor = PP_Streaming_v1AccessMock(Clones.clone(impl));

        _setUpOrchestrator(paymentProcessor);

        paymentProcessor.init(_orchestrator, _METADATA, bytes(""));

        _authorizer.setIsAuthorized(address(this), true);

        //Set up PaymentClient Correctöy
        impl = address(new ERC20PaymentClientBaseV1Mock());
        paymentClient = ERC20PaymentClientBaseV1Mock(Clones.clone(impl));

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
        assertEq(address(paymentProcessor.token()), address(_token));
    }

    function testSupportsInterface() public {
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPP_Streaming_v1).interfaceId
            )
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, bytes(""));
    }

    function testInit2StreamingPaymentProcessor() public {
        // Attempting to call the init2 function with malformed data
        // SHOULD FAIL
        vm.expectRevert(
            IModule_v1.Module__NoDependencyOrMalformedDependencyData.selector
        );
        paymentProcessor.init2(_orchestrator, abi.encode(123));

        // Calling init2 for the first time with no dependency
        // SHOULD FAIL
        bytes memory dependencyData = abi.encode(hasDependency, dependencies);
        vm.expectRevert(
            IModule_v1.Module__NoDependencyOrMalformedDependencyData.selector
        );
        paymentProcessor.init2(_orchestrator, dependencyData);

        // Calling init2 for the first time with dependency = true
        // SHOULD PASS
        dependencyData = abi.encode(true, dependencies);
        paymentProcessor.init2(_orchestrator, dependencyData);

        // Attempting to call the init2 function again.
        // SHOULD FAIL
        vm.expectRevert(IModule_v1.Module__CannotCallInit2Again.selector);
        paymentProcessor.init2(_orchestrator, dependencyData);
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
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + time
                })
            );

            totalAmount += amount;
        }

        // Call processPayments.
        vm.prank(address(paymentClient));

        for (uint i; i < recipients.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit StreamingPaymentAdded(
                address(paymentClient),
                recipients[i],
                amounts[i],
                block.timestamp,
                block.timestamp + durations[i],
                1
            );
            emit PaymentOrderProcessed(
                address(paymentClient),
                recipients[i],
                amounts[i],
                block.timestamp,
                block.timestamp + durations[i],
                1
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
            uint amount = uint(amounts[i]);
            uint time = uint(durations[i]);

            if (time > max_time) {
                max_time = time;
            }

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + time
                })
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
        assertEq(totalAmount, paymentClient.amountPaidCounter());
    }

    // @dev Assume recipient can withdraw full amount immediately if dueTo is less than or equal to block.timestamp.
    function testProcessPaymentsWorksForDueTimeThatIsPlacedBeforeStartTime(
        address[] memory recipients,
        uint[] memory dueTimes
    ) public {
        uint length = recipients.length;
        vm.assume(length < 50); //Restrict to reasonable size
        vm.assume(length <= dueTimes.length);

        assumeValidRecipients(recipients);

        // Warp to reasonable time to test wether orders before timestamp are retrievable
        vm.warp(1_680_220_800); // March 31, 2023 at 00:00 GMT

        //Amount of tokens for user that should be payed out
        uint payoutAmount = 100;

        for (uint i; i < length; i++) {
            // Add payment order to client.
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: payoutAmount,
                    createdAt: block.timestamp,
                    dueTo: dueTimes[i]
                })
            );
        }

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        // Call processPayments
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        for (uint i; i < length; i++) {
            address recipient = recipients[i];
            IERC20PaymentClientBase_v1.PaymentOrder memory order = orders[i];

            //If dueTo is before currentTimestamp evereything should be releasable
            if (order.dueTo <= block.timestamp) {
                assertEq(
                    paymentProcessor.releasableForSpecificWalletId(
                        address(paymentClient), address(recipient), 1
                    ),
                    payoutAmount
                );

                vm.prank(recipient);
                paymentProcessor.claimAll(address(paymentClient));

                // Check correct balances.
                assertEq(_token.balanceOf(recipient), payoutAmount);
                assertEq(
                    paymentProcessor.releasableForSpecificWalletId(
                        address(paymentClient), recipient, 1
                    ),
                    0
                );
            }
        }
    }

    function test_processPayments_discardsInvalidPaymentOrders() public {
        address[] memory recipients = createInvalidRecipients();

        uint invalidAmt = 0;

        vm.warp(1000);
        vm.startPrank(address(paymentClient));
        //we don't mind about adding address(this)in this case
        for (uint i = 0; i < recipients.length - 1; ++i) {
            paymentClient.addPaymentOrderUnchecked(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: 100,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + 100
                })
            );
        }
        //Expect the correct number and sequence of emits
        for (uint i = 0; i < recipients.length - 1; ++i) {
            vm.expectEmit(true, true, true, true);
            emit InvalidStreamingOrderDiscarded(
                recipients[i], 100, block.timestamp, block.timestamp + 100
            );
        }

        // Call processPayments and expect emits
        paymentProcessor.processPayments(paymentClient);

        paymentClient.addPaymentOrderUnchecked(
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: address(0xB0B),
                amount: invalidAmt,
                createdAt: block.timestamp,
                dueTo: block.timestamp + 100
            })
        );
        vm.expectEmit(true, true, true, true);
        emit InvalidStreamingOrderDiscarded(
            address(0xB0B), invalidAmt, block.timestamp, block.timestamp + 100
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
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + time
                })
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
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + time
                })
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Now, let's check whether all vesting informations exist or not
        // checking for paymentReceiver2
        IPP_Streaming_v1.VestingWallet[] memory paymentReceiverWallets;
        paymentReceiverWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver2
        );

        assertTrue(paymentReceiverWallets.length == 2);
        assertEq(
            (
                paymentReceiverWallets[0]._salary
                    + paymentReceiverWallets[1]._salary
            ),
            (amounts_1[1] + amounts_2[0]),
            "Improper accounting of orders"
        );

        // checking for paymentReceiver3
        paymentReceiverWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver3
        );

        assertTrue(paymentReceiverWallets.length == 2);
        assertEq(
            (
                paymentReceiverWallets[0]._salary
                    + paymentReceiverWallets[1]._salary
            ),
            (amounts_1[2] + amounts_2[1]),
            "Improper accounting of orders"
        );

        // checking for paymentReceiver 4
        paymentReceiverWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver4
        );

        assertTrue(paymentReceiverWallets.length == 1);
        assertEq(
            (paymentReceiverWallets[0]._salary),
            (amounts_2[2]),
            "Improper accounting of orders"
        );

        // checking for paymentReceiver 1
        paymentReceiverWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        assertTrue(paymentReceiverWallets.length == 1);
        assertEq(
            (paymentReceiverWallets[0]._salary),
            (amounts_1[0]),
            "Improper accounting of orders"
        );
    }

    uint initialNumWallets;
    uint initialPaymentReceiverBalance;
    uint initialWalletIdAtIndex1;
    uint finalNumWallets;
    uint finalPaymentReceiverBalance;

    function test_removePaymentForSpecificWalletId_halfVestingDoneMultipleOrdersForSingleBeneficiary(
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
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + time
                })
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Let's travel in time, to the point after paymentReceiver1's tokens for the second payment order
        // are 1/2 vested.
        vm.warp(block.timestamp + (durations[3] / 2));

        // This means, that when we call removePaymentForSpecificWalletId, that should increase the balance of the
        // paymentReceiver by 1/2 of the vested token amount
        IPP_Streaming_v1.VestingWallet[] memory paymentReceiverWallets =
        paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        // We are interested in finding the details of the 2nd wallet of paymentReceiver1
        uint expectedSalary = paymentReceiverWallets[1]._salary;
        uint walletId = paymentReceiverWallets[1]._vestingWalletID;

        initialNumWallets = paymentReceiverWallets.length;
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);
        initialWalletIdAtIndex1 = walletId;

        assertTrue(expectedSalary != 0);

        vm.prank(address(this)); // stupid line, ik, but it's just here to show that onlyOrchestratorOwner can call the next function
        paymentProcessor.removePaymentForSpecificWalletId(
            address(paymentClient), paymentReceiver1, walletId
        );

        paymentReceiverWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        finalNumWallets = paymentReceiverWallets.length;
        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(finalNumWallets + 1, initialNumWallets);
        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            (expectedSalary / 2)
        );
        //Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(paymentClient.amountPaidCounter(), expectedSalary);
        assertTrue(
            initialWalletIdAtIndex1
                != paymentReceiverWallets[1]._vestingWalletID
        );
    }

    uint salary1;
    uint salary2;
    uint salary3;
    uint amountPaidAlready;

    function test_removePaymentAndClaimForSpecificWalletId(
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

        // we want the durations of vesting for paymentReceiver 1 to be double of the initial one
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
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + time
                })
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Let's travel in time, to the point after paymentReceiver1's tokens for the second payment order
        // are 1/2 vested, or the complete vesting of duration of the first payment order
        vm.warp(block.timestamp + durations[0]);

        // Let's note down the current balance of the paymentReceiver1
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        IPP_Streaming_v1.VestingWallet[] memory paymentReceiverWallets =
        paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        salary1 = paymentReceiverWallets[0]._salary;

        // Now we claim the entire salary from the first payment order
        vm.prank(paymentReceiver1);
        paymentProcessor.claimForSpecificWalletId(
            address(paymentClient), paymentReceiverWallets[0]._vestingWalletID
        );

        // Now we note down the balance of the paymentReceiver1 again after claiming for the first wallet.
        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            salary1
        );

        //Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(paymentClient.amountPaidCounter(), salary1);
        amountPaidAlready += paymentClient.amountPaidCounter();

        // Now we are interested in finding the details of the 2nd wallet of paymentReceiver1
        salary2 = (paymentReceiverWallets[1]._salary) / 2; // since we are at half the vesting duration
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertTrue(salary2 != 0);

        vm.prank(address(this)); // stupid line, ik, but it's just here to show that onlyOrchestratorOwner can call the next function
        paymentProcessor.removePaymentForSpecificWalletId(
            address(paymentClient),
            paymentReceiver1,
            paymentReceiverWallets[1]._vestingWalletID
        );

        //Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(
            paymentClient.amountPaidCounter(),
            paymentReceiverWallets[1]._salary + salary1
        );
        amountPaidAlready = paymentClient.amountPaidCounter();

        paymentReceiverWallets = paymentProcessor.viewAllPaymentOrders(
            address(paymentClient), paymentReceiver1
        );

        finalNumWallets = paymentReceiverWallets.length;
        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(finalNumWallets, 1); // One was deleted because the vesting was completed and claimed. The other was deleted because of removePayment
        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            salary2
        );

        // Now we try and claim the 3rd payment order for paymentReceiver1
        // we are at half it's vesting period, so the salary3 should be half of the total salary
        // The third wallet is at the 0th index now, since the other 2 have been deleted due to removal and complete vesting.
        salary3 = (paymentReceiverWallets[0]._salary) / 2;
        initialPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        vm.prank(paymentReceiver1);
        paymentProcessor.claimForSpecificWalletId(
            address(paymentClient), paymentReceiverWallets[0]._vestingWalletID
        );
        //Make sure the paymentClient got the right amount of tokens removed from the outstanding mapping
        assertEq(paymentClient.amountPaidCounter() - amountPaidAlready, salary3);

        finalPaymentReceiverBalance = _token.balanceOf(paymentReceiver1);

        assertEq(
            (finalPaymentReceiverBalance - initialPaymentReceiverBalance),
            salary3
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

        ERC20PaymentClientBaseV1Mock otherERC20PaymentClient =
            new ERC20PaymentClientBaseV1Mock();

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
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: amounts[i],
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + duration
                })
            );
        }
        //Expect the correct number and sequence of emits
        for (uint i = 0; i < length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit StreamingPaymentAdded(
                address(paymentClient),
                recipients[i],
                amounts[i],
                block.timestamp,
                duration + block.timestamp,
                1
            );
            emit PaymentOrderProcessed(
                address(paymentClient),
                recipients[i],
                amounts[i],
                block.timestamp,
                duration + block.timestamp,
                1
            );
        }

        // Call processPayments and expect emits
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF to half the max_duration
        vm.warp(block.timestamp + 2 weeks);

        //we expect cancellation events for each payment
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
                paymentProcessor.startForSpecificWalletId(
                    address(paymentClient), recipient, 1
                ),
                0
            );
            assertEq(
                paymentProcessor.dueToForSpecificWalletId(
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

        ERC20PaymentClientBaseV1Mock otherERC20PaymentClient =
            new ERC20PaymentClientBaseV1Mock();

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

    //This test creates a new set of payments in a client which finished all running payments.
    //one possible case would be a orchestrator that finishes all milestones succesfully and then gets "restarted" some time later
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
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amounts[i],
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + durations[i]
                })
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF to half the max_duration
        vm.warp(max_duration / 2);

        // calling cancelRunningPayments also calls claim() so no need to repeat?
        vm.prank(address(paymentClient));
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
        uint length = recipients.length;
        vm.assume(length < 50); //Reasonable amount
        vm.assume(length <= amounts.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts, length);

        uint start = block.timestamp;
        uint duration = 1 weeks;

        for (uint i = 0; i < length; i++) {
            address recipient = recipients[i];
            uint amount = amounts[i];

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: start + duration
                })
            );
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

    function testClaimPreviouslyUnclaimable(address[] memory recipients)
        public
    {
        vm.assume(recipients.length < 30);

        for (uint i = 0; i < recipients.length; i++) {
            //If recipient is invalid change it
            if (recipients[i] == address(0) || recipients[i].code.length != 0) {
                recipients[i] = address(0x1);
            }
        }

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // Add payment order to client and call processPayments.

        for (uint i = 0; i < recipients.length; i++) {
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: 1,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp
                })
            );
            vm.prank(address(paymentClient));
            paymentProcessor.processPayments(paymentClient);

            //Immediately claim
            //This should shift right into unclaimable
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

            //Check that recipients are not handled twice
            if (recipientsHandled[recipient]) continue;
            recipientsHandled[recipient] = true;

            amount =
                paymentProcessor.unclaimable(address(paymentClient), recipient);

            //Grab Unclaimable Wallet Ids array
            uint[] memory ids = paymentProcessor.getUnclaimableWalletIds(
                address(paymentClient), recipient
            );

            //Do call
            vm.expectEmit(true, true, true, true);
            emit TokensReleased(recipient, address(_token), amount);

            vm.prank(recipient);
            paymentProcessor.claimPreviouslyUnclaimable(
                address(paymentClient), recipient
            );

            //Unclaimable amount for Wallet Ids empty (mapping)
            for (uint j = 0; j < ids.length; j++) {
                assertEq(
                    paymentProcessor.getUnclaimableAmountForWalletIds(
                        address(paymentClient), recipient, ids[j]
                    ),
                    0
                );
            }

            //Check Unclaimable Wallet Ids array empty
            assertEq(
                paymentProcessor.getUnclaimableWalletIds(
                    address(paymentClient), recipient
                ).length,
                0
            );

            //Amount send
            assertEq(_token.balanceOf(recipient), amount);

            //Check that amountPaid is correct in PaymentClient
            amountPaid += amount;
            assertEq(paymentClient.amountPaidCounter(), amountPaid);
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
            address(paymentClient), address(0x1)
        );
    }

    //This test creates a new set of payments in a client which finished all running payments. one possible case would be a orchestrator that finishes all milestones succesfully and then gets "restarted" some time later
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
            amount = uint(amounts[i]) * 2; //we paid two rounds
            totalAmount += amount;

            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient), address(recipient), 1
                ),
                0
            );
            assertEq(
                paymentProcessor.releasableForSpecificWalletId(
                    address(paymentClient), address(recipient), 2
                ),
                0
            );
        }

        // No funds left in the ERC20PaymentClientBase_v1
        assertEq(_token.balanceOf(address(paymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);

        assertEq(totalAmount, paymentClient.amountPaidCounter());
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
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipient,
                amount: amount,
                createdAt: block.timestamp,
                dueTo: block.timestamp + duration
            })
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // FF 25% and claim.
        vm.warp(block.timestamp + duration / 4);

        vm.expectEmit(true, true, true, true);
        emit UnclaimableAmountAdded(
            address(paymentClient), recipient, 1, amount / 4
        );

        vm.prank(recipient);
        paymentProcessor.claimAll(address(paymentClient));

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

        // claim the previously unclaimable amount
        vm.prank(recipient);
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), recipient
        );

        // after successful claim of the previously unclaimable amount the receiver should have 25% total,
        // while both 'releasable' and 'unclaimable' recipient's amounts should be 0
        assertEq(_token.balanceOf(address(recipient)), amount / 4);
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
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipient,
                amount: amount,
                createdAt: block.timestamp,
                dueTo: block.timestamp + duration
            })
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

        // claim the previously unclaimable amount
        vm.prank(recipient);
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), recipient
        );

        // after successful claim of the previously unclaimable amount the receiver should have 25% total,
        // while both 'releasable' and 'unclaimable' recipient's amounts should be 0
        assertEq(_token.balanceOf(address(recipient)), amount / 4);
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

    function testUnclaimable(address[] memory recipients) public {
        vm.assume(recipients.length < 30);

        for (uint i = 0; i < recipients.length; i++) {
            //If recipient is invalid change it
            if (recipients[i] == address(0) || recipients[i].code.length != 0) {
                recipients[i] = address(0x1);
            }
        }

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // Add payment order to client and call processPayments.

        for (uint i = 0; i < recipients.length; i++) {
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: 1,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp
                })
            );
            vm.prank(address(paymentClient));
            paymentProcessor.processPayments(paymentClient);

            //Immediately claim
            //This should shift right into unclaimable
            vm.prank(recipients[i]);
            paymentProcessor.claimAll(address(paymentClient));
        }

        uint amount;
        address recipient;
        for (uint i = 0; i < recipients.length; i++) {
            amount = 0;
            recipient = recipients[i];
            //if array contains address multiple times we check for repetitions
            for (uint j = 0; j < recipients.length; j++) {
                if (recipients[j] == recipient) {
                    amount += 1;
                }
            }
            assertEq(
                paymentProcessor.unclaimable(address(paymentClient), recipient),
                amount
            );
        }
    }

    //--------------------------------------------------------------------------
    // Helper functions

    // Speedruns a round of vesting + claiming
    // note Neither checks the inputs nor verifies results
    function speedRunStreamingAndClaim(
        address[] memory recipients,
        uint128[] memory amounts,
        uint64[] memory dueTos
    ) internal {
        uint max_time = dueTos[0];

        for (uint i; i < recipients.length; i++) {
            uint time = dueTos[i];

            if (time > max_time) {
                max_time = time;
            }

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: amounts[i],
                    createdAt: block.timestamp,
                    dueTo: block.timestamp + time
                })
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
