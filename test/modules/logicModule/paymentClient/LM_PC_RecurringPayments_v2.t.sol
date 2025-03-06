// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    LM_PC_RecurringPayments_v2,
    ILM_PC_RecurringPayments_v2,
    IERC20PaymentClientBase_v2
} from "@lm/LM_PC_RecurringPayments_v2.sol";

contract LM_PC_RecurringV1Test is ModuleTest {
    // SuT
    LM_PC_RecurringPayments_v2 recurringPaymentManager;

    uint private constant _SENTINEL = type(uint).max;
    bytes32 private constant _FLAGS_SET =
        0x000000000000000000000000000000000000000000000000000000000000000a;

    event RecurringPaymentAdded(
        uint indexed recurringPaymentId,
        uint amount,
        uint startEpoch,
        uint lastTriggeredEpoch,
        address recipient
    );
    event RecurringPaymentRemoved(uint indexed recurringPaymentId);
    event RecurringPaymentsTriggered(uint indexed currentEpoch);
    event EpochLengthSet(uint epochLength);

    function setUp() public {
        // Add Module to Mock Orchestrator_v1
        address impl = address(new LM_PC_RecurringPayments_v2());
        recurringPaymentManager = LM_PC_RecurringPayments_v2(Clones.clone(impl));

        _setUpOrchestrator(recurringPaymentManager);
        _authorizer.setIsAuthorized(address(this), true);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testSupportsInterface() public {
        assertTrue(
            recurringPaymentManager.supportsInterface(
                type(ILM_PC_RecurringPayments_v2).interfaceId
            )
        );
    }

    // This function also tests all the getters
    function testInit() public override(ModuleTest) {
        vm.expectRevert(
            ILM_PC_RecurringPayments_v2
                .Module__LM_PC_RecurringPayments__InvalidEpochLength
                .selector
        );

        vm.expectEmit(true, true, true, true);
        emit EpochLengthSet(1 weeks);

        // Init Module wrongly
        recurringPaymentManager.init(
            _orchestrator, _METADATA, abi.encode(1 weeks - 1)
        );

        vm.expectRevert(
            ILM_PC_RecurringPayments_v2
                .Module__LM_PC_RecurringPayments__InvalidEpochLength
                .selector
        );

        // Init Module wrongly
        recurringPaymentManager.init(
            _orchestrator, _METADATA, abi.encode(52 weeks + 1)
        );

        // Init Module correct
        recurringPaymentManager.init(
            _orchestrator, _METADATA, abi.encode(1 weeks)
        );

        assertEq(recurringPaymentManager.getEpochLength(), 1 weeks);

        assertEq(recurringPaymentManager.getFlagCount(), 2);
        bytes32 _START_END_FLAG =
            0x000000000000000000000000000000000000000000000000000000000000000a;
        assertEq(recurringPaymentManager.getFlags(), _START_END_FLAG);
    }

    function testReinitFails() public override(ModuleTest) {
        recurringPaymentManager.init(
            _orchestrator, _METADATA, abi.encode(1 weeks)
        );

        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        recurringPaymentManager.init(_orchestrator, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Modifier

    function testValidId(uint seed, uint usedIds, uint id) public {
        usedIds = bound(usedIds, 0, 1000);

        reasonableWarpAndInit(seed);

        for (uint i = 0; i < usedIds; i++) {
            recurringPaymentManager.addRecurringPayment(
                1, recurringPaymentManager.getCurrentEpoch(), address(0xBEEF)
            );
        }

        if (id > usedIds || id == 0) {
            vm.expectRevert(
                ILM_PC_RecurringPayments_v2
                    .Module__LM_PC_RecurringPayments__InvalidRecurringPaymentId
                    .selector
            );
        }

        recurringPaymentManager.getRecurringPaymentInformation(id);
    }

    function testValidStartEpoch(uint seed, uint startEpoch) public {
        reasonableWarpAndInit(seed);

        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();

        if (currentEpoch > startEpoch) {
            vm.expectRevert(
                ILM_PC_RecurringPayments_v2
                    .Module__LM_PC_RecurringPayments__InvalidStartEpoch
                    .selector
            );
        }

        recurringPaymentManager.addRecurringPayment(
            1, startEpoch, address(0xBeef)
        );
    }

    //--------------------------------------------------------------------------
    // Getter
    // Just test if Modifier is in position, because otherwise trivial

    function testGetRecurringPaymentInformationModifierInPosition() public {
        vm.expectRevert(
            ILM_PC_RecurringPayments_v2
                .Module__LM_PC_RecurringPayments__InvalidRecurringPaymentId
                .selector
        );
        recurringPaymentManager.getRecurringPaymentInformation(0);
    }

    //--------------------------------------------------------------------------
    // Epoch Functions
    // Trivial to test

    // Testing this for coverage
    function testGetFutureEpoch(uint seed) public {
        uint x = bound(seed, 0, 100_000_000); // Reasonable amount
        reasonableWarpAndInit(seed);

        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();
        assertEq(recurringPaymentManager.getFutureEpoch(x), currentEpoch + x);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    // AddRecurringPayment

    function testAddRecurringPayment(
        uint seed,
        uint amount,
        uint startEpoch,
        address recipient
    ) public {
        reasonableWarpAndInit(seed);

        // Assume correct inputs
        vm.assume(
            recipient != address(0)
                && recipient != address(recurringPaymentManager)
        );
        amount = bound(amount, 1, type(uint).max);
        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();
        startEpoch = bound(startEpoch, currentEpoch, type(uint).max);

        vm.expectEmit(true, true, true, true);
        emit RecurringPaymentAdded(
            1, // Id starts at 1
            amount,
            startEpoch,
            startEpoch - 1, // lastTriggeredEpoch has to be startEpoch - 1
            recipient
        );
        recurringPaymentManager.addRecurringPayment(
            amount, startEpoch, recipient
        );

        assertEqualRecurringPayment(
            1, amount, startEpoch, startEpoch - 1, recipient
        );

        // Check for multiple Adds
        uint id;
        uint length = bound(amount, 1, 30); // Reasonable amount
        for (uint i = 2; i < length + 2; i++) {
            vm.expectEmit(true, true, true, true);
            emit RecurringPaymentAdded(
                i, // Id starts at 1
                1,
                currentEpoch,
                currentEpoch - 1, // lastTriggeredEpoch has to be startEpoch - 1
                address(0xBEEF)
            );
            id = recurringPaymentManager.addRecurringPayment(
                1, currentEpoch, address(0xBEEF)
            );
            assertEq(id, i); // Maybe a bit overtested, that id is correct but ¯\_(ツ)_/¯
            assertEqualRecurringPayment(
                i, 1, currentEpoch, currentEpoch - 1, address(0xBEEF)
            );
        }
    }

    function testAddRecurringPaymentModifierInPosition() public {
        // Init Module
        recurringPaymentManager.init(
            _orchestrator, _METADATA, abi.encode(1 weeks)
        );

        // Warp to a reasonable time
        vm.warp(2 weeks);

        // onlyOrchestratorAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                address(0xBEEF)
            )
        );
        vm.prank(address(0xBEEF)); // Not Authorized
        recurringPaymentManager.addRecurringPayment(1, 2 weeks, address(0xBEEF));

        // validAmount
        vm.expectRevert(
            IERC20PaymentClientBase_v2
                .Module__ERC20PaymentClientBase__InvalidAmount
                .selector
        );
        recurringPaymentManager.addRecurringPayment(0, 2 weeks, address(0xBEEF));

        // validStartEpoch

        vm.expectRevert(
            ILM_PC_RecurringPayments_v2
                .Module__LM_PC_RecurringPayments__InvalidStartEpoch
                .selector
        );
        recurringPaymentManager.addRecurringPayment(1, 0, address(0xBEEF));

        // validRecipient

        vm.expectRevert(
            IERC20PaymentClientBase_v2
                .Module__ERC20PaymentClientBase__InvalidRecipient
                .selector
        );
        recurringPaymentManager.addRecurringPayment(1, 2 weeks, address(0));
    }

    //-----------------------------------------
    // RemoveRecurringPayment

    function testRemoveRecurringPayment(uint seed, uint amount) public {
        reasonableWarpAndInit(seed);
        amount = bound(amount, 1, 30); // Reasonable number of repetitions

        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();

        // Fund Fundingmanager
        _token.mint(address(_fundingManager), amount);

        // Fill list with RecurringPayments.
        for (uint i; i < amount; ++i) {
            recurringPaymentManager.addRecurringPayment(
                1, currentEpoch, address(0xBEEF)
            );
        }

        // Remove RecurringPayments from the front, i.e. lowest RecurringPayment id, until
        // list is empty.
        for (uint i; i < amount; ++i) {
            uint id = i + 1; // Note that id's start at 1.

            vm.expectEmit(true, true, true, true);
            emit RecurringPaymentRemoved(id);

            recurringPaymentManager.removeRecurringPayment(_SENTINEL, id);
            assertEq(
                recurringPaymentManager.listRecurringPaymentIds().length,
                amount - i - 1
            );
        }

        // Make sure that payments got triggered accordingly
        assertEq(recurringPaymentManager.paymentOrders().length, amount);

        // Delete all payments for easier testing
        _paymentProcessor.deleteAllPayments(
            IERC20PaymentClientBase_v2(address(recurringPaymentManager))
        );

        // Fund Fundingmanager
        _token.mint(address(_fundingManager), amount);

        // Fill list again with recurring payments.
        for (uint i; i < amount; ++i) {
            recurringPaymentManager.addRecurringPayment(
                1, currentEpoch, address(0xBEEF)
            );
        }

        // Remove recurring payments from the back, i.e. highest recurring payment id, until
        // list is empty.
        for (uint i; i < amount; ++i) {
            // Note that id's start at amount, because they have been created before.
            uint prevId = 2 * amount - i - 1;
            uint id = 2 * amount - i;

            // Note that removing the last recurring payment requires the sentinel as
            // prevId.
            if (prevId == amount) {
                prevId = _SENTINEL;
            }

            // Check if trigger was called
            vm.expectEmit(true, true, true, true);
            emit RecurringPaymentsTriggered(currentEpoch);

            vm.expectEmit(true, true, true, true);
            emit RecurringPaymentRemoved(id);

            recurringPaymentManager.removeRecurringPayment(prevId, id);
            assertEq(
                recurringPaymentManager.listRecurringPaymentIds().length,
                amount - i - 1
            );
        }

        // Make sure that payments got triggered accordingly
        assertEq(recurringPaymentManager.paymentOrders().length, amount);
    }

    function testRemoveRecurringPaymentModifierInPosition() public {
        // Init Module
        recurringPaymentManager.init(
            _orchestrator, _METADATA, abi.encode(1 weeks)
        );

        // onlyOrchestratorAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                address(0xBEEF)
            )
        );
        vm.prank(address(0xBEEF)); // Not Authorized
        recurringPaymentManager.removeRecurringPayment(0, 1);
    }

    //--------------------------------------------------------------------------
    // Trigger

    function testTrigger(uint seed, address[] memory receivers) public {
        vm.assume(receivers.length < 100 && receivers.length >= 3); // Reasonable amount

        receivers = convertToValidRecipients(receivers);

        uint timejumps = bound(seed, 1, 20);

        reasonableWarpAndInit(seed);

        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();

        // Generate appropriate Payment Orders
        createRecurringPaymentOrders(seed, receivers);

        // Mint enough tokens based on the payment order

        // Quick estimate: 1 token per payment Max receivers 100, max jumps 20, max epochs used in jump 4 -> 8000 tokens needed (lets go with 10k)
        // note to 1 token: im not testing if the paymentProcessor works just if it creates payment orders accordingly
        _token.mint(address(_fundingManager), 10_000);

        // Copy Payments for later comparison
        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory
            recurringPaymentsToBeChecked = fetchRecurringPayments();

        // Payout created Payments via trigger
        vm.expectEmit(true, true, true, true);
        emit RecurringPaymentsTriggered(currentEpoch);
        recurringPaymentManager.trigger();

        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory
            currentRecurringPayments = fetchRecurringPayments();

        // compare that Orders were placed and lastTriggered got updated accordingly
        recurringPaymentsAreCorrect(
            recurringPaymentsToBeChecked, currentRecurringPayments, currentEpoch
        );

        // remove tokens and orders from recurringPaymentManager for easier testing
        _paymentProcessor.deleteAllPayments(
            IERC20PaymentClientBase_v2(address(recurringPaymentManager))
        );
        _token.burn(
            address(recurringPaymentManager),
            _token.balanceOf(address(recurringPaymentManager))
        );

        // Do a timejump and check again
        for (uint i = 0; i < timejumps; i++) {
            // Update Payments for later comparison
            recurringPaymentsToBeChecked = fetchRecurringPayments();

            vm.warp(
                block.timestamp
                    + bound(
                        seed, // Introduce some randomness for the jump
                        recurringPaymentManager.getEpochLength(),
                        recurringPaymentManager.getEpochLength() * 4 // In case someone forgets to trigger -> Minimum one Month max 4 years
                    )
            );
            currentEpoch = recurringPaymentManager.getCurrentEpoch();
            vm.expectEmit(true, true, true, true);
            emit RecurringPaymentsTriggered(currentEpoch);
            recurringPaymentManager.trigger();

            currentRecurringPayments = fetchRecurringPayments();

            // compare that Orders were placed and lastTriggered got updated accordingly
            recurringPaymentsAreCorrect(
                recurringPaymentsToBeChecked,
                currentRecurringPayments,
                currentEpoch
            );

            // remove tokens and orders from recurringPaymentManager for easier testing
            _paymentProcessor.deleteAllPayments(
                IERC20PaymentClientBase_v2(address(recurringPaymentManager))
            );
            _token.burn(
                address(recurringPaymentManager),
                _token.balanceOf(address(recurringPaymentManager))
            );
        }
    }

    function testTriggerFor(
        uint seed,
        address[] memory receivers,
        uint startId,
        uint endId
    ) public {
        vm.assume(receivers.length < 100 && receivers.length >= 3); // Reasonable amount

        endId = bound(endId, 1, receivers.length);
        startId = bound(startId, 1, endId);

        receivers = convertToValidRecipients(receivers);

        reasonableWarpAndInit(seed);

        // Generate appropriate Payment Orders
        createRecurringPaymentOrders(seed, receivers);

        // Mint enough tokens based on the payment order

        // Quick estimate: 1 token per payment Max receivers 100, max epochs used in jump 4 -> 400 tokens needed (lets go with 500)
        // note to 1 token: im not testing if the paymentProcessor works just if it creates payment orders accordingly
        _token.mint(address(_fundingManager), 500);

        // Copy Payments for later comparison
        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory
            filteredRecurringPaymentsToBeChecked =
                filterPayments(fetchRecurringPayments(), startId, endId);

        vm.warp(
            block.timestamp
                + bound(
                    seed, // Introduce some randomness for the jump
                    0,
                    recurringPaymentManager.getEpochLength() * 4 // In case someone forgets to trigger -> Minimum one Month max 4 years
                )
        );
        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();

        vm.expectEmit(true, true, true, true);
        emit RecurringPaymentsTriggered(currentEpoch);
        recurringPaymentManager.triggerFor(startId, endId);

        // Get currentPayments and filter them
        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory
            currentRecurringPayments =
                filterPayments(fetchRecurringPayments(), startId, endId);

        // compare that Orders were placed and lastTriggered got updated accordingly
        recurringPaymentsAreCorrect(
            filteredRecurringPaymentsToBeChecked,
            currentRecurringPayments,
            currentEpoch
        );
    }

    function testTriggerForModifierInPosition(uint seed) public {
        reasonableWarpAndInit(seed);

        recurringPaymentManager.addRecurringPayment(
            1, recurringPaymentManager.getCurrentEpoch(), address(0xBEEF)
        );

        recurringPaymentManager.addRecurringPayment(
            1, recurringPaymentManager.getCurrentEpoch(), address(0xBEEF)
        );

        vm.expectRevert(
            ILM_PC_RecurringPayments_v2
                .Module__LM_PC_RecurringPayments__InvalidRecurringPaymentId
                .selector
        );
        recurringPaymentManager.triggerFor(0, 1);

        vm.expectRevert(
            ILM_PC_RecurringPayments_v2
                .Module__LM_PC_RecurringPayments__InvalidRecurringPaymentId
                .selector
        );
        recurringPaymentManager.triggerFor(1, 0);

        vm.expectRevert(
            ILM_PC_RecurringPayments_v2
                .Module__LM_PC_RecurringPayments__StartIdNotBeforeEndId
                .selector
        );
        recurringPaymentManager.triggerFor(2, 1);
    }

    // =========================================================================

    //--------------------------------------------------------------------------
    // Helper

    function reasonableWarpAndInit(uint seed) internal {
        uint epochLength = bound(seed, 1 weeks, 52 weeks);

        // with this we are at least in epoch 2 and there is enough time to go on from that time (3_153_600_000 seconds are 100 years)
        uint currentTimestamp = bound(seed, 52 weeks + 1, 3_153_600_000);

        // Warp to a reasonable time
        vm.warp(currentTimestamp);

        // Init Module
        recurringPaymentManager.init(
            _orchestrator, _METADATA, abi.encode(epochLength)
        );
    }

    function convertToValidRecipients(address[] memory addrs)
        internal
        view
        returns (address[] memory)
    {
        uint length = addrs.length;
        // Convert address(0) to address (1)
        for (uint i; i < length; i++) {
            if (
                addrs[i] == address(0)
                    || addrs[i] == address(recurringPaymentManager)
            ) addrs[i] = address(0x1);
        }

        return addrs;
    }

    function assertEqualRecurringPayment(
        uint idToProve,
        uint amount,
        uint startEpoch,
        uint lastTriggeredEpoch,
        address recipient
    ) internal {
        ILM_PC_RecurringPayments_v2.RecurringPayment memory payment =
            recurringPaymentManager.getRecurringPaymentInformation(idToProve);

        assertEq(payment.amount, amount);
        assertEq(payment.startEpoch, startEpoch);
        assertEq(payment.lastTriggeredEpoch, lastTriggeredEpoch);
        assertEq(payment.recipient, recipient);
    }

    function createRecurringPaymentOrders(uint seed, address[] memory receiver)
        internal
    {
        uint length = receiver.length;

        uint currentEpoch = recurringPaymentManager.getCurrentEpoch();

        uint startEpoch;
        uint growingSequenceBefore;
        uint growingSequenceCurrent;
        for (uint i; i < length; i++) {
            // This is a way to introduce randomness and grow the startEpoch in reasonable steps
            growingSequenceCurrent = growingSequenceBefore + i;

            startEpoch = currentEpoch
                + bound(seed, growingSequenceBefore, growingSequenceCurrent);

            growingSequenceBefore = growingSequenceCurrent;

            recurringPaymentManager.addRecurringPayment(
                1, startEpoch, receiver[i]
            );
        }
    }

    function fetchRecurringPayments()
        internal
        view
        returns (ILM_PC_RecurringPayments_v2.RecurringPayment[] memory)
    {
        uint[] memory ids = recurringPaymentManager.listRecurringPaymentIds();
        uint length = ids.length;

        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory recurringPayments =
            new ILM_PC_RecurringPayments_v2.RecurringPayment[](length);

        for (uint i = 0; i < length; i++) {
            recurringPayments[i] =
                recurringPaymentManager.getRecurringPaymentInformation(ids[i]);
        }
        return recurringPayments;
    }

    function filterPayments(
        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory paymentsToFilter,
        uint startId,
        uint endId
    )
        internal
        pure
        returns (ILM_PC_RecurringPayments_v2.RecurringPayment[] memory)
    {
        uint filterArrayLength = endId - startId + 1; // even if endId and startId are the same its at least one order
        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory returnArray = new ILM_PC_RecurringPayments_v2
            .RecurringPayment[](filterArrayLength);
        for (uint i = 0; i < filterArrayLength; i++) {
            returnArray[i] = paymentsToFilter[startId - 1 + i]; // because ids start at 1 substract 1 to get appropriate array position
        }
        return returnArray;
    }

    // Note: this needs the old version of the orders before the trigger function was called to work
    function recurringPaymentsAreCorrect(
        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory
            recurringPaymentsToBeChecked,
        ILM_PC_RecurringPayments_v2.RecurringPayment[] memory
            currentRecurringPayments,
        uint currentEpoch
    ) internal {
        uint length = recurringPaymentsToBeChecked.length;

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            recurringPaymentManager.paymentOrders();
        assertEq(length, currentRecurringPayments.length);

        // prediction of how many orders have to be created for this recurring payment
        uint epochsTriggered;

        // Amount of tokens that should be in the LM_PC_RecurringPayments_v2
        uint totalAmount;

        // Amount of tokens in a single order
        uint orderAmount;

        ILM_PC_RecurringPayments_v2.RecurringPayment memory
            currentRecurringPaymentToBeChecked;

        // Because some of the RecurringPaymentOrders start only in the future we have to have a seperate index for that
        uint numberOfOrdersMade;

        for (uint i; i < length; i++) {
            currentRecurringPaymentToBeChecked = recurringPaymentsToBeChecked[i];
            // Orders are only created if lastTriggeredEpoch is smaller than currentEpoch
            if (
                currentEpoch
                    > currentRecurringPaymentToBeChecked.lastTriggeredEpoch
            ) {
                epochsTriggered = currentEpoch
                    - currentRecurringPaymentToBeChecked.lastTriggeredEpoch;

                assertOrder(
                    orders[numberOfOrdersMade],
                    currentRecurringPaymentToBeChecked.recipient,
                    currentRecurringPaymentToBeChecked.amount,
                    block.timestamp,
                    (currentEpoch + 1)
                        * recurringPaymentManager.getEpochLength()
                );

                if (epochsTriggered > 1) {
                    numberOfOrdersMade++;

                    assertOrder(
                        orders[numberOfOrdersMade],
                        currentRecurringPaymentToBeChecked.recipient,
                        currentRecurringPaymentToBeChecked.amount
                            * (epochsTriggered - 1),
                        block.timestamp,
                        (currentEpoch)
                            * recurringPaymentManager.getEpochLength()
                    );

                    orderAmount = currentRecurringPaymentToBeChecked.amount
                        * epochsTriggered;
                } else {
                    orderAmount = currentRecurringPaymentToBeChecked.amount;
                }

                totalAmount += orderAmount;
                numberOfOrdersMade++;
                // Check if updated payment lastTriggeredEpoch is current epoch
                assertEq(
                    currentRecurringPayments[i].lastTriggeredEpoch, currentEpoch
                );
            }
        }
    }

    function assertOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        address recipient,
        uint amount,
        uint start,
        uint end
    ) internal {
        assertEq(order.recipient, recipient);

        assertEq(order.amount, amount);
        // if first three flags are set the flags array is 0x07
        assertEq(order.flags, _FLAGS_SET);

        uint decodedStart = uint(order.data[0]);
        uint decodedEnd = uint(order.data[1]);

        assertEq(decodedStart, start);
        assertEq(decodedEnd, end);
    }
}
