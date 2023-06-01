// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// SuT
import {
    ConcurrentStreamingPaymentProcessor,
    IPaymentProcessor
} from "src/modules/ConcurrentStreamingPaymentProcessor.sol";

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
        uint duration
    );

    event StreamingPaymentRemoved(
        address indexed paymentClient, address indexed recipient
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
                    address(paymentClient), address(recipient), block.timestamp, 1
                ),
                0
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
