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

    function testUpdatePayments(address[] memory recipients,
        uint128[] memory amounts) public {
            //@todo
    }
    

    // TODO: do when VestingProcessor is finished.
/* 
    function testUpdateAndRestartPayments(address[] memory recipients,
        uint128[] memory amounts, uint64[] memory durations
    ) public {
        vm.assume(recipients.length <= amounts.length);
        vm.assume(amounts.length <= durations.length);
        assumeValidRecipients(recipients);
        assumeValidAmounts(amounts);
        assumeValidDurations(durations);

        //add first batch of payment orders. 
        // @dev To have different values, we multiply the amounts supplied by foundry. Since we are casting to uint256, we don't overflow 
        
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]);
            uint duration = uint(durations[i]);

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, duration
            );
        }

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);


        //check everything is alright

        //warp to some point in the future
        vm.warp(block.timestamp + (3 days));


        // now, at some point in vesting, we add the next batch, which updates the balances + times for some, or restarts for others
        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]);
            uint duration = uint(durations[i]);

            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, duration);
        }

        // Call processPayments.
        paymentProcessor.processPayments(paymentClient);

        //warp a bit more
        vm.warp(block.timestamp + (3 days));

        //go through all recipients



        for (uint i; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint amount = uint(amounts[i]*2);
            uint duration = uint(durations[i]*2);


            // Add payment order to client.
            paymentClient.addPaymentOrder(
                recipient, amount, (block.timestamp + duration)
            );

            // Call processPayments.
            paymentProcessor.processPayments(paymentClient);

            //some (but not all) time passes
            vm.warp(block.timestamp + duration/2);

            uint amtBefore = _token.balanceOf(address(recipient));

            vm.prank(address(recipient));
            paymentProcessor.claim(paymentClient);

            uint amtClaimed = _token.balanceOf(address(recipient)) - amtBefore;

            // Check correct balances.
            assertEq(amtClaimed, (amount/2)+amtBefore);
            assertEq(_token.balanceOf(address(paymentClient)), amount-amtClaimed);

            // Invariant: Payment processor does not hold funds.
            assertEq(_token.balanceOf(address(paymentProcessor)), 0);




        }



        // @todo
    } */

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
