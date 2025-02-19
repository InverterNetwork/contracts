// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

//--------------------------------------------------------------------------
// Imports
// External Dependencies

import {Test} from "forge-std/Test.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {IERC20Errors} from "@oz/interfaces/draft-IERC6093.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import "forge-std/console2.sol";

// Internal Dependencies
import {PP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/PP_Connext_Crosschain_v1.sol";
import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IPP_Crosschain_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_Crosschain_v1.sol";
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

// Tests and Mocks
import {CrossChainBase_v1_Exposed} from
    "test/utils/mocks/modules/paymentProcessor/CrossChainBase_v1_Exposed.sol";
import {PP_Connext_Crosschain_v1_Exposed} from
    "test/utils/mocks/modules/paymentProcessor/PP_Connext_Crosschain_v1_Exposed.sol";
import {Mock_EverclearPayment} from
    "test/utils/mocks/external/Mock_EverclearPayment.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_Connext_Crosschain_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    // Constants
    uint constant MINTED_SUPPLY = 1000 ether;
    uint constant ZERO_AMOUNT = 0;
    //--------------------------------------------------------------------------
    // Test Storage
    PP_Connext_Crosschain_v1_Exposed public paymentProcessor;
    Mock_EverclearPayment public everclearPaymentMock;
    ERC20PaymentClientBaseV2Mock paymentClient;
    IPP_Crosschain_v1 public crossChainBase;
    IWETH public weth;

    // Bridge-related storage
    address public mockConnextBridge;
    address public mockEverClearSpoke;
    address public mockWeth;

    // Execution data storage
    uint maxFee = 0;
    uint ttl = 1;
    bytes executionData;
    bytes invalidExecutionData;

    //--------------------------------------------------------------------------
    // Setup Function

    function setUp() public {
        // Prepare execution data for bridge operations
        executionData = abi.encode(maxFee, ttl);
        invalidExecutionData = abi.encode(address(0));

        // Deploy mock contracts and set addresses
        everclearPaymentMock = new Mock_EverclearPayment();
        mockEverClearSpoke = address(everclearPaymentMock);
        mockWeth = address(weth);

        // Deploy payment processor via clone
        address impl = address(new PP_Connext_Crosschain_v1_Exposed());
        paymentProcessor = PP_Connext_Crosschain_v1_Exposed(Clones.clone(impl));

        _setUpOrchestrator(paymentProcessor);
        _authorizer.setIsAuthorized(address(this), true);

        // Initialize payment processor with config
        bytes memory configData = abi.encode(mockEverClearSpoke, mockWeth);
        paymentProcessor.init(_orchestrator, _METADATA, configData);

        // Deploy and add payment client through timelock process
        impl = address(new ERC20PaymentClientBaseV2Mock());
        paymentClient = ERC20PaymentClientBaseV2Mock(Clones.clone(impl));
        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));

        // Configure payment client
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);

        _setupInitialBalances();
    }

    //--------------------------------------------------------------------------
    // Initialization Tests

    /* Test initialization
    */
    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    /* Test interface support
    */
    function testSupportsInterface() public {
        // Test for IModule_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(type(IModule_v1).interfaceId)
        );

        // Test for ICrossChainBase_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(
                type(ICrossChainBase_v1).interfaceId
            )
        );

        // Test for a non-supported interface (using a random interface ID)
        assertFalse(paymentProcessor.supportsInterface(0xffffffff));
    }

    /* Test reinitialization
    */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, abi.encode(1));
    }

    //--------------------------------------------------------------------------
    // Payment Processing Tests

    /* Test single payment processing
    └── Given single valid payment order
        └── When processing cross-chain payments
            └── Then it should emit PaymentProcessed events for payment
                └── And it should create cross-chain intent
    */
    function testFuzz_PublicProcessPayments_succeedsGivenSingleValidPaymentOrder(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit IPaymentProcessor_v1.PaymentOrderProcessed(
            address(paymentClient),
            testRecipient,
            address(_token),
            testAmount,
            0,
            0,
            bytes32(0),
            new bytes32[](0)
        );
        // emit IPaymentProcessor_v1.PaymentOrderProcessed(
        //     address(paymentClient),
        //     testRecipient,
        //     address(_token),
        //     testAmount,
        //     0,
        //     block.timestamp + 1 days
        // );

        // Process payments
        paymentProcessor.processPayments(client);
        assertEq(_token.balanceOf(address(testRecipient)), 0);
        console2.log(_token.balanceOf(address(testRecipient)));
        assertEq(_token.balanceOf(address(mockEverClearSpoke)), testAmount);

        bytes32 intentId = paymentProcessor.getProcessedIntentId(
            address(paymentClient),
            testRecipient,
            paymentProcessor.getPaymentId()
        );
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(Mock_EverclearPayment.IntentStatus.ADDED)
        );
    }

    /* Test single payment outstanding token amounts
    └── Given a single valid payment order
        └── When processing cross-chain payments
            └── Then it should verify the outstanding token amounts
    */
    function testFuzz_PublicProcessPayments_verifyOutstandingTokenAmounts(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        assertEq(client.outstandingTokenAmount(address(_token)), testAmount);
        paymentProcessor.processPayments(client);
        assertEq(client.outstandingTokenAmount(address(_token)), 0);
    }

    /* Test multiple payment processing
    └── Given multiple valid payment orders
        └── When processing cross-chain payments
            └── Then it should emit PaymentProcessed events for each payment
                └── And it should create multiple cross-chain intents
    */
    function testFuzz_PublicProcessPayments_succeedsGivenMultipleValidPaymentOrders(
        uint8 numRecipients,
        uint testAmount
    ) public {
        vm.assume(numRecipients > 0 && numRecipients <= 10);
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY);

        // Setup mock payment orders
        address[] memory setupRecipients = new address[](numRecipients);
        uint[] memory setupAmounts = new uint[](numRecipients);

        for (uint i = 0; i < numRecipients; i++) {
            setupRecipients[i] = address(
                uint160(uint(keccak256(abi.encodePacked(i, block.timestamp))))
            );
            setupAmounts[i] =
                1 + (uint64(uint(keccak256(abi.encode(i, testAmount)))));
        }

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _createPaymentOrders(numRecipients, setupRecipients, setupAmounts);

        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        // Expect events for each payment
        for (uint i = 0; i < numRecipients; i++) {
            vm.expectEmit(true, true, true, true);
            emit IPaymentProcessor_v1.PaymentOrderProcessed(
                address(paymentClient),
                setupRecipients[i],
                address(_token),
                setupAmounts[i],
                0,
                0,
                bytes32(0),
                new bytes32[](0)
            );
            // emit IPaymentProcessor_v1.PaymentOrderProcessed(
            //     address(paymentClient),
            //     setupRecipients[i],
            //     address(_token),
            //     setupAmounts[i],
            //     0,
            //     block.timestamp + 1 days
            // );
        }

        // Process payments
        paymentProcessor.processPayments(client);

        uint totalAmount = 0;
        //should be checking in the mock for valid bridge data
        for (uint i = 0; i < numRecipients; i++) {
            bytes32 intentId = paymentProcessor.getProcessedIntentId(
                address(paymentClient), setupRecipients[i], i + 1
            );
            assertEq(
                uint(everclearPaymentMock.status(intentId)),
                uint(Mock_EverclearPayment.IntentStatus.ADDED)
            );
            totalAmount += setupAmounts[i];
        }
        assertEq(_token.balanceOf(address(mockEverClearSpoke)), totalAmount);
    }

    /* Test multiple payment outstanding token amounts
    └── Given multiple valid payment orders
        └── When processing cross-chain payments
            └── Then it should verify the outstanding token amounts for each payment
    */
    function testFuzz_PublicProcessPaymentsMultiple_verifyOutstandingTokenAmounts(
        uint8 numRecipients,
        uint testAmount
    ) public {
        vm.assume(numRecipients > 0 && numRecipients <= 10);
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY);

        // Setup mock payment orders
        address[] memory setupRecipients = new address[](numRecipients);
        uint[] memory setupAmounts = new uint[](numRecipients);

        uint OutstandingAmount = 0;

        for (uint i = 0; i < numRecipients; i++) {
            setupRecipients[i] = address(
                uint160(uint(keccak256(abi.encodePacked(i, block.timestamp))))
            );
            setupAmounts[i] =
                1 + (uint64(uint(keccak256(abi.encode(i, testAmount)))));
            OutstandingAmount += setupAmounts[i];
        }

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _createPaymentOrders(numRecipients, setupRecipients, setupAmounts);

        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        assertEq(
            client.outstandingTokenAmount(address(_token)), OutstandingAmount
        );
        // Process payments
        paymentProcessor.processPayments(client);
        assertEq(client.outstandingTokenAmount(address(_token)), 0);
    }

    /* Test empty payment processing
    └── Given no payment orders
        └── When processing payments
            └── Then it should complete successfully
                └── And bridge data should remain empty
    */

    function testFuzz_PublicProcessPayments_succeedsGivenNoPaymentOrders()
        public
    {
        // Process payments and verify _bridgeData mapping is not updated
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) == keccak256(bytes("")),
            "Bridge data should be empty"
        );
        assertEq(
            paymentProcessor.getProcessedIntentId(
                address(paymentClient),
                address(0),
                paymentProcessor.getPaymentId()
            ),
            bytes32(0)
        );
    }

    //--------------------------------------------------------------------------
    // Error Case Tests

    function testFuzz_PublicProcessPayments_revertsGivenInvalidExecutionData(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount);

        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        // Process payments
        vm.expectRevert();
        paymentProcessor.processPayments(client);
        // paymentProcessor.processPayments(client, invalidExecutionData);
    }

    /* Test empty execution data
        ├── Given empty execution data bytes
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidExecutionData
    */
    // function testFuzz_PublicProcessPayments_revertsGivenEmptyExecutionData(
    //     address testRecipient,
    //     uint testAmount
    // ) public {
    //     _assumeValidRecipientAndAmount(testRecipient, testAmount);
    //     _setupSinglePayment(testRecipient, testAmount);

    //     // Get the client interface
    //     IERC20PaymentClientBase_v2 client =
    //         IERC20PaymentClientBase_v2(address(paymentClient));

    //     // Process payments
    //     vm.expectRevert(
    //         ICrossChainBase_v1
    //             .Module__CrossChainBase_InvalidExecutionData
    //             .selector
    //     );
    // @note I removed the revert in the Connect crosschain implementation and instead added a revert in in the processPayments function.
    //     paymentProcessor.processPayments(client);
    // }

    /* Test invalid recipient
        ├── Given a payment order with address(0) recipient
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidRecipient
    */
    // function testFuzz_PublicProcessPayments_revertsGivenInvalidRecipient(
    //     uint testAmount
    // ) public {
    //     vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance

    //     _setupSinglePayment(address(0), testAmount);
    //     // Get the client interface
    //     IERC20PaymentClientBase_v2 client =
    //         IERC20PaymentClientBase_v2(address(paymentClient));

    //     // Process payments
    //     vm.expectRevert(
    //         ICrossChainBase_v1.Module__CrossChainBase__InvalidRecipient.selector
    //     );
    // @note I removed the revert in the Connect crosschain implementation and instead added a revert in in the processPayments function.
    //     paymentProcessor.processPayments(client);
    // }

    /* Test invalid amount
        ├── Given a payment order with zero amount
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidAmount
    */
    // function testFuzz_PublicProcessPayments_revertsGivenInvalidAmount(
    //     address testRecipient
    // ) public {
    //     vm.assume(testRecipient != address(0));

    //     _setupSinglePayment(testRecipient, 0);
    //     // Get the client interface
    //     IERC20PaymentClientBase_v2 client =
    //         IERC20PaymentClientBase_v2(address(paymentClient));

    //     // Process payments
    //     vm.expectRevert(
    //         ICrossChainBase_v1.Module__CrossChainBase__InvalidAmount.selector
    //     );
    // @note I removed the revert in the Connect crosschain implementation as to add a payment order, it has to be valid first.
    //     paymentProcessor.processPayments(client);
    // }

    /* Test bridge data storage
        ├── Given a valid payment order
        │   └── When processing payment
        │       └── Then bridge data should not be empty
        │           └── And intent ID should be stored correctly
                    └── And intent status should be ADDED in Everclear spoke
    */
    function testFuzz_PublicProcessPayments_worksGivenCorrectBridgeData(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        // Process payments and verify _bridgeData mapping is updated
        paymentProcessor.processPayments(client);
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) != keccak256(bytes("")),
            "Bridge data should not be empty"
        );

        bytes32 intentId = bytes32(paymentProcessor.getBridgeData(0));
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(Mock_EverclearPayment.IntentStatus.ADDED)
        );
    }

    /* Test empty bridge data
        ── When checking bridge data with no added payments
            └── Then it should return empty bytes
    */
    function testFuzz_PublicProcessPayments_succeedsGivenEmptyBridgeData()
        public
    {
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        // Process payments and verify _bridgeData mapping is updated
        paymentProcessor.processPayments(client);
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) == keccak256(bytes("")),
            "Bridge data should be empty"
        );
    }

    /* Test insufficient balance
        └── Given payment amount exceeds available balance
            └── When attempting to process payment
                └── Then it should revert with ERC20InsufficientBalance
    */
    function testFuzz_PublicProcessPayments_revertsGivenInsufficientBalance(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount);

        vm.prank(testRecipient);
        _token.transfer(address(0xDEAD), testAmount);
        assertEq(_token.balanceOf(address(testRecipient)), 0);

        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        console2.log(address(paymentProcessor));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                testRecipient,
                _token.balanceOf(testRecipient),
                testAmount
            )
        );
        paymentProcessor.processPayments(client);
    }

    /* Test edge case amounts
        └── Given payment processor has exactly required amount
            └── When processing payment
                └── Then it should process successfully
                    └── And should emit PaymentProcessed event
                    └── And should handle exact balance correctly
    */
    function testFuzz_PublicProcessPayments_worksGivenEdgeCaseAmounts(
        address testRecipient,
        uint96 testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup - Clear existing balance
        uint currentBalance = _token.balanceOf(address(paymentProcessor));
        if (currentBalance > 0) {
            vm.prank(address(paymentProcessor));
            _token.transfer(address(0xDEAD), currentBalance);
        }

        // Setup - Mint exact amount needed
        _token.mint(address(paymentProcessor), testAmount);

        // Setup - Configure payment
        _setupSinglePayment(testRecipient, testAmount);

        // Expectations
        vm.expectEmit(true, true, true, true);
        emit IPaymentProcessor_v1.PaymentOrderProcessed(
            address(paymentClient),
            testRecipient,
            address(_token),
            testAmount,
            0,
            0,
            bytes32(0),
            new bytes32[](0)
        );
        // emit IPaymentProcessor_v1.PaymentOrderProcessed(
        //     address(paymentClient),
        //     testRecipient,
        //     address(_token),
        //     testAmount,
        //     0,
        //     block.timestamp + 1 days
        // );

        // Action - Process payments
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test retry failed transfer
    └── Given a failed transfer
        └── When retrying with valid execution data
            └── Then it should create a new intent
                └── And clear the failed transfer record
                └── And emit FailedTransferRetried event
    */

    function testFuzz_PublicRetryFailedTransfer_succeedsGivenValidFailedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount);

        // Store the initial execution data that will fail
        bytes memory failingExecutionData = abi.encode(333, 1); // maxFee of 333 will cause failure
        // First attempt with high maxFee to force failure
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        // paymentProcessor.processPayments(
        //     IERC20PaymentClientBase_v2(address(paymentClient)),
        //     failingExecutionData
        // );

        // Verify failed transfer was recorded with the failing execution data
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), testRecipient
            ),
            testAmount
        );

        // Now retry with proper execution data
        vm.prank(address(paymentClient));
        paymentProcessor.retryFailedBridgeTransfer(
            address(paymentClient), testRecipient, orders[0]
        );

        // Verify:
        // 1. Failed transfer record was cleared
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), testRecipient
            ),
            0
        );

        // 2. New intent was created (should be non-zero)
        bytes32 newIntentId = paymentProcessor.getProcessedIntentId(
            address(paymentClient),
            testRecipient,
            paymentProcessor.getPaymentId()
        );
        assertTrue(newIntentId != bytes32(0));
    }

    /* Test claim previously unclaimable
    └── Given a pending transfer
        └── When claimed by the recipient
            └── Then it should clear the intent
                └── And return funds to recipient
                └── And emit UnclaimableAmountClaimed event
    */
    function testFuzz_PublicClaimUnclaimable_succeedsGivenValidPendingTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup the payment and process it
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount);

        uint balanceBefore = _token.balanceOf(address(paymentProcessor));
        bytes memory executionData = abi.encode(333, 1);
        //call processPayments with maxFee = 333
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        uint balanceAfter = _token.balanceOf(address(paymentProcessor));
        assertEq(balanceAfter, balanceBefore + testAmount);

        // see if failed unclaimable amount updates
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), testRecipient
            ),
            orders[0].amount
        );

        uint balanceBeforeCancel = _token.balanceOf(address(paymentProcessor));
        // Cancel as recipient
        vm.prank(testRecipient);
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), testRecipient
        );
        uint balanceAfterCancel = _token.balanceOf(address(paymentProcessor));

        assertEq(balanceAfterCancel, balanceBeforeCancel - testAmount);

        // Verify intentId was cleared
        assertEq(
            paymentProcessor.getProcessedIntentId(
                address(paymentClient),
                testRecipient,
                paymentProcessor.getPaymentId()
            ),
            bytes32(0)
        );
    }

    /* Test claim by non-recipient
    └── Given a pending transfer
        └── When claimed by someone other than recipient
            └── Then it should revert with NothingToClaim
    */
    function testFuzz_PublicClaimUnclaimable_revertsGivenNonRecipientCaller(
        address testRecipient,
        address nonRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount);

        // Process payment to create intent
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        bytes32 pendingIntentId = paymentProcessor.getProcessedIntentId(
            address(paymentClient),
            testRecipient,
            paymentProcessor.getPaymentId()
        );

        // Create payment order for cancellation
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: testRecipient,
            paymentToken: address(_token),
            amount: testAmount,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: testRecipient,
        //     paymentToken: address(_token),
        //     amount: testAmount,
        //     start: block.timestamp,
        //     cliff: 0,
        //     end: block.timestamp + 1 days
        // });

        // Prank as non-recipient
        console2.log(address(paymentClient));
        vm.prank(nonRecipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__NothingToClaim
                    .selector,
                address(paymentClient),
                nonRecipient
            )
        );
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), testRecipient
        );
    }

    /* Test claim after processing
    └── Given a successfully processed payment
        └── When attempting to claim unclaimable
            └── Then it should revert with NothingToClaim
                └── And the intent ID should remain unchanged
                └── And the payment order should remain processed
    */
    function testFuzz_PublicClaimUnclaimable_revertsGivenProcessedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment and process it
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount);

        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Cancel the transfer
        vm.prank(testRecipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__NothingToClaim
                    .selector,
                address(paymentClient),
                testRecipient
            )
        );
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), testRecipient
        );
    }

    /* Test TTL validation
    └── Given execution data with zero TTL
        └── When processing payments
            └── Then it should revert with InvalidTTL
    */
    function testFuzz_ProcessPayments_revertsWithZeroTTL(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        _setupSinglePayment(testRecipient, testAmount);

        bytes memory zeroTTLData = abi.encode(maxFee, 0);
        vm.expectRevert();
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        // paymentProcessor.processPayments(
        //     IERC20PaymentClientBase_v2(address(paymentClient)), zeroTTLData
        // );
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test retry with invalid client
    └── Given a retry request from non-client address
        └── When retrying failed transfer
            └── Then it should revert with InvalidAddress
    */
    function testFuzz_PublicRetryFailedTransfer_revertsGivenInvalidCaller(
        address testRecipient,
        uint testAmount,
        address invalidCaller
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        vm.assume(invalidCaller != address(paymentClient));

        // Setup failed transfer
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount);

        bytes memory failingExecutionData = abi.encode(333, 1);
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        // paymentProcessor.processPayments(
        //     IERC20PaymentClientBase_v2(address(paymentClient)),
        //     failingExecutionData
        // );

        // Attempt retry from invalid caller
        vm.prank(invalidCaller);
        vm.expectRevert(
            IPaymentProcessor_v1
                .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                .selector
        );
        paymentProcessor.retryFailedBridgeTransfer(
            address(paymentClient), testRecipient, orders[0]
        );
    }

    /* Test retry with no failed transfer record
    └── Given a retry request for non-existent failed transfer
        └── When retrying transfer
            └── Then it should revert with InvalidAmount
    */
    function testFuzz_PublicRetryFailedTransfer_revertsGivenNoFailedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount);

        vm.prank(address(paymentClient));
        vm.expectRevert(
            IPP_Crosschain_v1
                .Module__PP_Crosschain__InvalidUnclaimableAmount
                .selector
        );
        paymentProcessor.retryFailedBridgeTransfer(
            address(paymentClient), testRecipient, orders[0]
        );
    }

    /* Test retry with existing intent
    └── Given a retry request when intent already exists
        └── When retrying transfer
            └── Then it should revert with InvalidIntentId
    */
    function testFuzz_PublicRetryFailedTransfer_revertsGivenExistingIntent(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment and process it
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount);

        // Create a successful intent first
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Now try to retry (should fail because intent exists)
        vm.prank(address(paymentClient));
        vm.expectRevert();
        paymentProcessor.retryFailedBridgeTransfer(
            address(paymentClient), testRecipient, orders[0]
        );
    }

    /* Test retry with invalid execution data
    └── Given a retry request with invalid execution data
        └── When retrying failed transfer
            └── Then it should revert with InvalidExecutionData
    */
    function testFuzz_PublicRetryFailedTransfer_revertsGivenInvalidExecutionData(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup failed transfer
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount);

        bytes memory failingExecutionData = abi.encode(333, 1);
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        // paymentProcessor.processPayments(
        //     IERC20PaymentClientBase_v2(address(paymentClient)),
        //     failingExecutionData
        // );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPP_Crosschain_v1
                    .Module__PP_Crosschain__MessageDeliveryFailed
                    .selector,
                8453,
                8453,
                failingExecutionData
            )
        );
        paymentProcessor.retryFailedBridgeTransfer(
            address(paymentClient), testRecipient, orders[0]
        );
    }

    /* Test process payments without token approval
    └── Given a payment order with zero approval
        └── When attempting to process payment
            └── Then it should revert with InvalidTokenApproval
    */
    function testFuzz_PublicProcessPayments_revertsGivenNoTokenApproval(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount);

        // Reset approval
        vm.prank(testRecipient);
        _token.approve(address(paymentProcessor), 0);

        // Expect revert for insufficient allowance
        console2.log(_token.balanceOf(address(testRecipient)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(paymentProcessor),
                0,
                testAmount
            )
        );
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test payment processing with unsupported token
    └── Given a payment order with an unsupported token
    └── When attempting to process payment
        └── Then it should revert with UnsupportedToken
    */
    function testFuzz_PublicProcessPayments_revertsGivenUnsupportedToken(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup payment with unsupported token
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: testRecipient,
            paymentToken: address(0xDEADBEEF), // Unsupported token address
            amount: testAmount,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        paymentClient.exposed_addPaymentOrder(order);

        // Expect revert due to unsupported token
        vm.expectRevert();
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test payment processing with zero token balance
    └── Given payment processor has zero token balance
        └── When processing payments
            └── Then it should revert with ERC20InsufficientBalance
    */
    // function testFuzz_PublicProcessPayments_revertsGivenZeroBalance(
    //     address testRecipient
    // ) public {
    //     vm.assume(testRecipient != address(0));

    //     _setupSinglePayment(testRecipient, ZERO_AMOUNT);
    //     assertEq(_token.balanceOf(address(testRecipient)), ZERO_AMOUNT);
    //     vm.expectRevert(
    //         ICrossChainBase_v1.Module__CrossChainBase__InvalidAmount.selector
    //     );
    // @note I removed the revert in the Connect crosschain implementation and instead added a revert in in the processPayments function.

    //     paymentProcessor.processPayments(
    //         IERC20PaymentClientBase_v2(address(paymentClient))
    //     );
    // }

    /* Test payment processing with duplicate recipients
    └── Given payment orders with duplicate recipients
    └── When processing payments
        └── Then it should handle duplicates correctly
            └── And update intent IDs properly
            └── And track total amounts correctly
    */
    function testFuzz_PublicProcessPayments_succeedsGivenDuplicateRecipients(
        address testRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));

        // Create multiple orders for same recipient
        address[] memory recipients = new address[](3);
        uint[] memory amounts = new uint[](3);

        for (uint i = 0; i < 3; i++) {
            recipients[i] = testRecipient;
            vm.assume(testAmount > 0 && testAmount <= MINTED_SUPPLY);
            amounts[i] = testAmount;
        }

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _createPaymentOrders(3, recipients, amounts);

        vm.prank(testRecipient);
        _token.approve(address(paymentProcessor), type(uint).max);

        // Process payments
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Verify final intent ID exists
        bytes32 finalIntentId = paymentProcessor.getProcessedIntentId(
            address(paymentClient),
            testRecipient,
            paymentProcessor.getPaymentId()
        );
        assertTrue(finalIntentId != bytes32(0));
    }

    /* Test payment processing with varying start/end times
    └── Given payment orders with different time configurations
    └── When processing payments
        └── Then it should handle valid time ranges
            └── And revert for invalid ones
    */
    function testFuzz_PublicProcessPayments_succeedsGivenVariableTimeRanges(
        address testRecipient,
        uint testAmount,
        uint32 timeOffset
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        vm.assume(timeOffset > 0 && timeOffset < 30 days);

        // Create payment order with fuzzed time range
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: testRecipient,
        //     paymentToken: address(_token),
        // amount: testAmount,
        // start: block.timestamp,
        // cliff: 0,
        // end: block.timestamp + timeOffset
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: testRecipient,
            paymentToken: address(_token),
            amount: testAmount,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        _token.mint(testRecipient, testAmount);
        vm.prank(testRecipient);
        _token.approve(address(paymentProcessor), testAmount);
        paymentClient.exposed_addPaymentOrder(order);

        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        bytes32 intentId = paymentProcessor.getProcessedIntentId(
            address(paymentClient),
            testRecipient,
            paymentProcessor.getPaymentId()
        );
        assertTrue(intentId != bytes32(0));
    }

    function testFuzz_PublicProcessPayments_succeedsGivenExpiredEndDate(
        address testRecipient,
        uint testAmount
    ) public {
        //@audit-issue -> discuss with 33 about this test
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup payment with expired end date
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: testRecipient,
            paymentToken: address(_token),
            amount: testAmount,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: testRecipient,
        //     paymentToken: address(_token),
        //     amount: testAmount,
        //     start: block.timestamp - 2 days,
        //     cliff: 0, //@note 33audits -> shouldnt this revert since start and end time are in the past?
        //     end: block.timestamp - 1 days // End date in the past
        // });

        // Mint tokens to recipient
        _token.mint(testRecipient, testAmount);
        vm.prank(testRecipient);
        _token.approve(address(paymentProcessor), testAmount);

        paymentClient.exposed_addPaymentOrder(order);

        // Process payments
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        assertEq(_token.balanceOf(testRecipient), 0);
        console2.log(_token.balanceOf(address(testRecipient)));
        assertEq(_token.balanceOf(address(mockEverClearSpoke)), testAmount);
    }

    //--------------------------------------------------------------------------
    // Payment Order Validation Tests

    /* Test invalid recipient
    └── Given a payment order with address(0) recipient
        └── When validating the payment order
            └── Then it should return false
    */
    function testPublicValidPaymentOrder_revertsGivenInvalidRecipient()
        public
    {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0),
            paymentToken: address(_token),
            amount: 1,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: address(0),
        //     paymentToken: address(_token),
        //     amount: 1,
        //     start: block.timestamp,
        //     cliff: 0,
        //     end: block.timestamp + 1 days
        // });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test invalid token
    └── Given a payment order with address(0) token
        └── When validating the payment order
            └── Then it should return false
    */
    function testFuzz_PublicValidPaymentOrder_revertsGivenInvalidToken()
        public
    {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(0),
            amount: 1,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: address(0xBEEF),
        //     paymentToken: address(0),
        //     amount: 1,
        //     start: block.timestamp,
        //     cliff: 0,
        //     end: block.timestamp + 1 days
        // });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test invalid amount
    └── Given a payment order with zero amount
        └── When validating the payment order
            └── Then it should return false
    */
    function testPublicValidPaymentOrder_revertsGivenInvalidAmount() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(_token),
            amount: 0,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(_token),
            amount: 0,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: address(0xBEEF),
        //     paymentToken: address(_token),
        //     amount: 0,
        //     start: block.timestamp,
        //     cliff: 0,
        //     end: block.timestamp + 1 days
        // });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test invalid start
    └── Given a payment order with start time after end time
        └── When validating the payment order
            └── Then it should return false
    */
    function testPublicValidPaymentOrder_revertsGivenInvalidStart() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(_token),
            amount: 1,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: address(0xBEEF),
        //     paymentToken: address(_token),
        //     amount: 1,
        //     start: block.timestamp + 1 days,
        //     cliff: 0,
        //     end: block.timestamp
        // });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test invalid cliff
    └── Given a payment order with cliff time after end time
        └── When validating the payment order
            └── Then it should return false
    */
    function testPublicValidPaymentOrder_revertsGivenInvalidCliff() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(_token),
            amount: 1,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: address(0xBEEF),
        //     paymentToken: address(_token),
        //     amount: 1,
        //     start: block.timestamp,
        //     cliff: 1 days,
        //     end: block.timestamp - 1 days
        // });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test valid payment order
    └── Given a valid payment order
        └── When validating the payment order
            └── Then it should return true
    */
    function testPublicValidPaymentOrder_succeeds() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(_token),
            amount: 1,
            originChainId: 0,
            targetChainId: 0,
            flags: bytes32(0),
            data: new bytes32[](0)
        });
        // IERC20PaymentClientBase_v2.PaymentOrder({
        //     recipient: address(0xBEEF),
        //     paymentToken: address(_token),
        //     amount: 1,
        //     start: block.timestamp,
        //     cliff: 0,
        //     end: block.timestamp + 1 days
        // });
        assertEq(paymentProcessor.validPaymentOrder(order), true);
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function _setupSinglePayment(address _recipient, uint _amount)
        internal
        returns (IERC20PaymentClientBase_v2.PaymentOrder[] memory)
    {
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = _recipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = _amount;

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        return orders;
    }

    function _createPaymentOrders(
        uint orderCount,
        address[] memory recipients,
        uint[] memory amounts
    ) internal returns (IERC20PaymentClientBase_v2.PaymentOrder[] memory) {
        // Sanity checks for array lengths
        require(
            recipients.length == orderCount && amounts.length == orderCount,
            "Array lengths must match orderCount"
        );
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            new IERC20PaymentClientBase_v2.PaymentOrder[](orderCount);

        for (uint i = 0; i < orderCount; i++) {
            if (recipients[i] != address(0)) {
                //mint tokens to recipient & approve payment processor
                _token.mint(recipients[i], amounts[i]);
                vm.prank(recipients[i]);
                _token.approve(address(paymentProcessor), amounts[i]);
            }
            orders[i] = IERC20PaymentClientBase_v2.PaymentOrder({
                recipient: recipients[i],
                paymentToken: address(_token),
                amount: amounts[i],
                originChainId: 0,
                targetChainId: 0,
                flags: bytes32(0),
                data: new bytes32[](0)
            });
            // orders[i] = IERC20PaymentClientBase_v2.PaymentOrder({
            //     recipient: recipients[i],
            //     paymentToken: address(_token),
            //     amount: amounts[i],
            //     start: block.timestamp,
            //     cliff: 0,
            //     end: block.timestamp + 1 days
            // });
            //add payment order to client
            paymentClient.exposed_addPaymentOrder(orders[i]);
        }
        return orders;
    }

    function _setupInitialBalances() internal {
        // Setup token approvals and initial balances
        _token.mint(address(this), MINTED_SUPPLY);
        _token.approve(address(paymentProcessor), type(uint).max);

        _token.mint(address(paymentProcessor), MINTED_SUPPLY); // Mint _tokens to processor
        vm.prank(address(paymentProcessor));
        _token.approve(address(paymentProcessor), type(uint).max); // Processor approves bridge logic
    }

    function _assumeValidRecipientAndAmount(
        address testRecipient,
        uint testAmount
    ) internal pure {
        vm.assume(testRecipient != address(0));
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY);
    }
}
