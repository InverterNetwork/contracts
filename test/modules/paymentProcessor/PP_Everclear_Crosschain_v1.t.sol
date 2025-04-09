// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal Imports
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IPP_CrossChainBase_v1} from "@pp/interfaces/IPP_CrossChainBase_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IPP_Everclear_CrossChain_v1} from
    "@pp/interfaces/IPP_Everclear_CrossChain_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

// External Imports
import {Clones} from "@oz/proxy/Clones.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {IEverclear} from "@pp/interfaces/IEverclear.sol";

// Tests and Mocks
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {EverclearPaymentMock} from
    "test/utils/mocks/external/EverclearPaymentMock.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// SuT
import {PP_Everclear_CrossChain_v1_Exposed} from
    "test/modules/paymentProcessor/PP_Everclear_CrossChain_v1_Exposed.sol";

contract PP_Everclear_CrossChain_v1_Test is ModuleTest {
    // ========================================================================
    // Constants

    uint constant MINTED_SUPPLY = 1000 ether;
    uint public constant MAX_CALLDATA_SIZE = 50_000;
    uint32 constant EVERCLEAR_ID = 1122;

    // ========================================================================
    // State

    PP_Everclear_CrossChain_v1_Exposed public paymentProcessor;
    EverclearPaymentMock public everclearPaymentMock;
    ERC20PaymentClientBaseV2Mock paymentClient;
    IPP_CrossChainBase_v1 public CrossChainBase;

    // Bridge-related storage
    address public mockConnextBridge;
    address public mockEverClearSpoke;

    // Chain IDs
    uint ORIGIN_CHAIN_ID;
    uint TARGET_CHAIN_ID;

    // Execution data storage
    bytes32[] public EMPTY_EXECUTION_DATA = new bytes32[](6);
    uint FLAG_MAX_FEE = 4;
    uint FLAG_TTL = 5;

    // ========================================================================
    // Setup
    function setUp() public {
        // Deploy mock contracts and set addresses
        everclearPaymentMock = new EverclearPaymentMock();
        mockEverClearSpoke = address(everclearPaymentMock);

        // Deploy and setup the payment client for testing SUT
        address impl = address(new ERC20PaymentClientBaseV2Mock());
        paymentClient = ERC20PaymentClientBaseV2Mock(Clones.clone(impl));

        // Deploy and init the SUT
        impl = address(new PP_Everclear_CrossChain_v1_Exposed());
        paymentProcessor =
            PP_Everclear_CrossChain_v1_Exposed(Clones.clone(impl));

        // Setup the mock workflow contracts and token
        _setUpOrchestrator(paymentClient);

        // Initialize the SUT
        bytes memory configData = abi.encode(mockEverClearSpoke);
        paymentProcessor.init(_orchestrator, _METADATA, configData);

        // Initialize payment client
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);

        // Set the testing contract to be authorized in authorizer mock
        _authorizer.setIsAuthorized(address(this), true);

        // Set Chain IDs
        ORIGIN_CHAIN_ID = block.chainid;
        TARGET_CHAIN_ID = 1337;
    }

    // ========================================================================
    // Test Init & SupportsInterface

    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.getEverClearSpoke()), mockEverClearSpoke
        );
    }

    function testSupportsInterface() public {
        // Test for IPP_CrossChainBase_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPP_CrossChainBase_v1).interfaceId
            )
        );
        // Test for IPP_Everclear_CrossChain_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPP_Everclear_CrossChain_v1).interfaceId
            )
        );
        // Test for IPaymentProcessor_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPaymentProcessor_v1).interfaceId
            )
        );
        // Test for a non-supported interface (using a random interface ID)
        assertFalse(paymentProcessor.supportsInterface(0xffffffff));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, abi.encode(1));
    }

    // ========================================================================
    // Test External (public + external)

    /*  Test: Function getIntentByIntentId()
        └── Given an intent has been stored
            └── When the function getIntentByIntentId is called
                └── Then it should return the intent
    */
    function testgetIntentByIntentId_worksGivenIntentReturned(
        bytes32 intentId_,
        bytes32 initiator_,
        bytes32 receiver_,
        bytes32 inputAsset_,
        bytes32 outputAsset_,
        uint24 maxFee_
    ) public {
        // Create mock intent
        IEverclear.Intent memory intent = IEverclear.Intent({
            initiator: initiator_,
            receiver: receiver_,
            inputAsset: inputAsset_,
            outputAsset: outputAsset_,
            maxFee: maxFee_,
            origin: 0,
            nonce: 0,
            timestamp: uint48(0),
            ttl: uint48(0),
            amount: 0,
            destinations: new uint32[](0),
            data: bytes("")
        });
        // Set the intent
        paymentProcessor.helper_setIntentIdToIntent(intentId_, intent);

        // Test function call
        IEverclear.Intent memory returnedIntent =
            paymentProcessor.getIntentByIntentId(intentId_);

        // post-assert
        // Only test some fields for validation to validate the intent is set correctly
        assertEq(returnedIntent.initiator, initiator_);
        assertEq(returnedIntent.receiver, receiver_);
        assertEq(returnedIntent.inputAsset, inputAsset_);
        assertEq(returnedIntent.outputAsset, outputAsset_);
        assertEq(returnedIntent.maxFee, maxFee_);
    }

    /*  Test: Function processPayments()
        └── Given single valid payment order
            └── When processing cross-chain payments
                └── Then it should emit PaymentProcessed events for payment
                    └── And it should create cross-chain intent
    */

    function testProcessPayments_worksGivenSingleValidPaymentOrder(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);

        // Prepare expected event data
        bytes32[] memory expectedExecutionData = _getExecutionData();

        // Expect event with specific parameters
        vm.expectEmit(true, true, true, true);
        emit IPaymentProcessor_v1.PaymentOrderProcessed(
            address(paymentClient),
            testRecipient,
            address(_token),
            testAmount,
            ORIGIN_CHAIN_ID,
            TARGET_CHAIN_ID,
            bytes32(uint(0x3F)),
            expectedExecutionData
        );
        vm.prank(address(paymentClient));
        // Execute the transaction
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        assertEq(_token.balanceOf(address(mockEverClearSpoke)), testAmount);
        bytes32 intentId = bytes32(paymentProcessor.getBridgeDataByPaymentId(0));
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(EverclearPaymentMock.IntentStatus.ADDED)
        );
    }

    /*  Test: Function processPayments()
        └── Given a single valid payment order
            └── When processing cross-chain payments
                └── Then it should verify the outstanding token amounts
    */
    function testProcessPayments_worksGivenOutstandingTokenAmounts(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        assertEq(client.outstandingTokenAmount(address(_token)), testAmount);
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(client);
        assertEq(client.outstandingTokenAmount(address(_token)), 0);
    }

    /* Test: Function processPayments()
        └── Given multiple valid payment orders
            └── When processing cross-chain payments
                └── Then it should emit PaymentProcessed events for each payment
                    └── And it should create multiple cross-chain intents
    */
    function testProcessPayments_worksGivenMultipleValidPaymentOrders(
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

        _createPaymentOrders(
            numRecipients, setupRecipients, setupAmounts, EMPTY_EXECUTION_DATA
        );

        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        bytes32[] memory executionData = _getExecutionData();

        // Expect events for each payment
        for (uint i = 0; i < numRecipients; i++) {
            vm.expectEmit(true, true, true, true);
            emit IPaymentProcessor_v1.PaymentOrderProcessed(
                address(paymentClient),
                setupRecipients[i],
                address(_token),
                setupAmounts[i],
                ORIGIN_CHAIN_ID,
                TARGET_CHAIN_ID,
                bytes32(uint(0x3F)), // Binary: ...0011 1111
                executionData
            );
        }
        vm.prank(address(paymentClient));
        // Process payments
        paymentProcessor.processPayments(client);

        uint totalAmount = 0;
        //should be checking in the mock for valid bridge data
        for (uint i = 0; i < numRecipients; i++) {
            bytes32 intentId =
                bytes32(paymentProcessor.getBridgeDataByPaymentId(i));
            assertEq(
                uint(everclearPaymentMock.status(intentId)),
                uint(EverclearPaymentMock.IntentStatus.ADDED)
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
    function testProcessPayments_worksGivenMultipleOutstandingTokenAmounts(
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

        _createPaymentOrders(
            numRecipients, setupRecipients, setupAmounts, EMPTY_EXECUTION_DATA
        );

        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        assertEq(
            client.outstandingTokenAmount(address(_token)), OutstandingAmount
        );
        vm.prank(address(paymentClient));
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

    function testProcessPayments_succeedsGivenNoPaymentOrders() public {
        // Process payments and verify _paymentIdToBridgeData mapping is not updated
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        assertTrue(
            keccak256(paymentProcessor.getBridgeDataByPaymentId(0))
                == keccak256(bytes("")),
            "Bridge data should be empty"
        );
        assertEq(
            bytes32(
                paymentProcessor.getBridgeDataByPaymentId(
                    paymentProcessor.getPaymentId()
                )
            ),
            bytes32(0)
        );
    }
    //--------------------------------------------------------------------------
    // Error Case Tests

    function testProcessPayments_revertsGivenInvalidExecutionData(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        bytes32[] memory customExecutionData = _getExecutionData();
        customExecutionData[5] = bytes32(uint(0)); //set TTL to 0
        _setupSinglePayment(testRecipient, testAmount, customExecutionData);

        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        // Process payments
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                    .selector
            )
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(client);
    }

    /* Test empty execution data
        └── Given empty execution data bytes
            └── When attempting to process payment
                └── Then it should revert with InvalidExecutionData
    */
    function testProcessPayments_revertsGivenEmptyExecutionData(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        bytes32[] memory customExecutionData = _getExecutionData();
        // Create payment order with fuzzed time range
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: testRecipient,
            paymentToken: address(_token),
            amount: testAmount,
            originChainId: ORIGIN_CHAIN_ID,
            targetChainId: TARGET_CHAIN_ID,
            flags: bytes32(0),
            data: customExecutionData
        });

        paymentClient.exposed_addPaymentOrder(order);

        vm.expectRevert(
            IERC20PaymentClientBase_v2
                .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                .selector
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test invalid recipient
        └── Given a payment order with address(0) recipient
            └── When attempting to process payment
                └── Then it should revert with InvalidRecipient
    */
    function testProcessPayments_revertsGivenInvalidRecipient(uint testAmount)
        public
    {
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance

        _setupSinglePayment(address(0), testAmount, EMPTY_EXECUTION_DATA);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        // Process payments
        vm.expectRevert(
            IERC20PaymentClientBase_v2
                .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                .selector
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(client);
    }

    /* Test invalid amount
        └── Given a payment order with zero amount
            └── When attempting to process payment
                └── Then it should revert with InvalidAmount
    */
    function testProcessPayments_revertsGivenInvalidAmount(
        address testRecipient
    ) public {
        vm.assume(testRecipient != address(0));

        _setupSinglePayment(testRecipient, 0, EMPTY_EXECUTION_DATA);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        // Process payments
        vm.expectRevert(
            IERC20PaymentClientBase_v2
                .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                .selector
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(client);
    }

    /* Test bridge data storage
        └── Given a valid payment order
            └── When processing payment
                ├── Then bridge data should not be empty
                ├── And intent ID should be stored correctly
                └── And intent status should be ADDED in Everclear spoke
    */
    function testProcessPayments_worksGivenCorrectBridgeData(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        vm.prank(address(paymentClient));
        // Process payments and verify _paymentIdToBridgeData mapping is updated
        paymentProcessor.processPayments(client);
        assertTrue(
            keccak256(paymentProcessor.getBridgeDataByPaymentId(0))
                != keccak256(bytes("")),
            "Bridge data should not be empty"
        );

        bytes32 intentId = bytes32(paymentProcessor.getBridgeDataByPaymentId(0));
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(EverclearPaymentMock.IntentStatus.ADDED)
        );
    }

    /* Test empty bridge data
        └── When checking bridge data with no added payments
            └── Then it should return empty bytes
    */
    function testProcessPayments_succeedsGivenEmptyBridgeData() public {
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        // Process payments and verify _paymentIdToBridgeData mapping is updated
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(client);
        assertTrue(
            keccak256(paymentProcessor.getBridgeDataByPaymentId(0))
                == keccak256(bytes("")),
            "Bridge data should be empty"
        );
    }

    /* Test edge case amounts
        └── Given payment processor has exactly required amount
            └── When processing payment
                ├── Then it should process successfully
                ├── And should emit PaymentProcessed event
                └── And should handle exact balance correctly
    */
    function testProcessPayments_worksGivenEdgeCaseAmounts(
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

        // Setup - Configure payment
        _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);
        // Action - Process payments
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test Function retryFailedBridgeTransfer()
        └── Given a failed transfer
            └── When retrying with valid execution data
                ├── Then it should create a new intent
                ├── And clear the failed transfer record
                └── And emit FailedTransferRetried event
    */

    function testRetryFailedTransfer_succeedsGivenValidFailedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);

        // First attempt with high maxFee to force failure
        everclearPaymentMock.setMockBridgeToFail(true);
        vm.prank(address(paymentClient));
        //approve the token to the payment processor
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Verify failed transfer was recorded with the failing execution data
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), testRecipient
            ),
            testAmount
        );

        // Now retry with proper execution data
        everclearPaymentMock.setMockBridgeToFail(false);

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
        bytes32 newIntentId = bytes32(
            paymentProcessor.getBridgeDataByPaymentId(
                paymentProcessor.getPaymentId() - 1
            )
        );
        assertTrue(newIntentId != bytes32(0));
    }

    /* Test claim previously unclaimable
        └── Given a pending transfer
            └── When claimed by the recipient
                ├── Then it should clear the intent
                ├── And return funds to recipient
                └── And emit UnclaimableAmountClaimed event
    */
    function testClaimUnclaimable_succeedsGivenValidPendingTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup the payment and process it
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);

        uint balanceBefore = _token.balanceOf(address(paymentProcessor));
        everclearPaymentMock.setMockBridgeToFail(true); //Force the bridge transfer to fail
        vm.prank(address(paymentClient));
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
            bytes32(
                paymentProcessor.getBridgeDataByPaymentId(
                    paymentProcessor.getPaymentId()
                )
            ),
            bytes32(0)
        );
    }

    /* Test claim by non-recipient
        └── Given a pending transfer
            └── When claimed by someone other than recipient
                └── Then it should revert with NothingToClaim
    */
    function testClaimUnclaimable_revertsGivenNonRecipientCaller(
        address testRecipient,
        address nonRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);
        vm.prank(address(paymentClient));
        // Process payment to create intent
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Prank as non-recipient
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
                ├── Then it should revert with NothingToClaim
                ├── And the intent ID should remain unchanged
                └── And the payment order should remain processed
    */
    function testClaimUnclaimable_revertsGivenProcessedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment and process it
        _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);
        vm.prank(address(paymentClient));
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
    function testProcessPayments_revertsWithZeroTTL(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        bytes32[] memory customExecutionData = _getExecutionData();
        customExecutionData[5] = bytes32(uint(0)); // set TTL to 0
        _setupSinglePayment(testRecipient, testAmount, customExecutionData);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                    .selector
            )
        );
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test Function retryFailedBridgeTransfer()
        └── Given a retry request for non-existent failed transfer
            └── When retrying transfer
                └── Then it should revert with InvalidAmount
    */
    function testRetryFailedTransfer_revertsGivenNoFailedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);

        vm.prank(address(paymentClient));
        vm.expectRevert(
            IPP_CrossChainBase_v1
                .Module__PP_CrossChain__InvalidUnclaimableAmount
                .selector
        );
        paymentProcessor.retryFailedBridgeTransfer(
            address(paymentClient), testRecipient, orders[0]
        );
    }

    /* Test Function retryFailedBridgeTransfer()
        └── Given a retry request when intent already exists
            └── When retrying transfer
                └── Then it should revert with InvalidIntentId
    */
    function testRetryFailedTransfer_revertsGivenExistingIntent(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment and process it
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount, EMPTY_EXECUTION_DATA);
        vm.prank(address(paymentClient));
        // Create a successful intent first
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Now try to retry (should fail because intent exists)
        vm.prank(address(paymentClient));
        vm.expectRevert(
            IPP_CrossChainBase_v1
                .Module__PP_CrossChain__InvalidUnclaimableAmount
                .selector
        );
        paymentProcessor.retryFailedBridgeTransfer(
            address(paymentClient), testRecipient, orders[0]
        );
    }

    /* Test payment processing with unsupported token
        └── Given a payment order with an unsupported token
        └── When attempting to process payment
            └── Then it should revert with UnsupportedToken
    */
    function testProcessPayments_revertsGivenUnsupportedToken(
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
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test payment processing with duplicate recipients
        └── Given payment orders with duplicate recipients
            └── When processing payments
                ├── Then it should handle duplicates correctly
                └── And update intent IDs properly
                └── And track total amounts correctly
    */
    function testProcessPayments_succeedsGivenDuplicateRecipients(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Create multiple orders for same recipient
        address[] memory recipients = new address[](3);
        uint[] memory amounts = new uint[](3);

        for (uint i = 0; i < 3; i++) {
            recipients[i] = testRecipient;
            amounts[i] = testAmount;
        }

        _createPaymentOrders(3, recipients, amounts, EMPTY_EXECUTION_DATA);
        vm.prank(address(paymentClient));
        // Process payments
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Verify final intent ID exists
        bytes32 finalIntentId = bytes32(
            paymentProcessor.getBridgeDataByPaymentId(
                paymentProcessor.getPaymentId() - 1
            )
        );
        assertTrue(finalIntentId != bytes32(0));
    }

    /* Test payment processing with varying start/end times
        └── Given payment orders with different time configurations
            └── When processing payments
                ├── Then it should handle valid time ranges
                └── And revert for invalid ones
    */
    function testProcessPayments_succeedsGivenVariableTimeRanges(
        address testRecipient,
        uint testAmount,
        uint32 timeOffset
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        vm.assume(timeOffset > 0 && timeOffset < 30 days);

        bytes32[] memory customExecutionData = _getExecutionData();
        customExecutionData[3] = bytes32(uint(block.timestamp + timeOffset));
        // Create payment order with fuzzed time range
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: testRecipient,
            paymentToken: address(_token),
            amount: testAmount,
            originChainId: ORIGIN_CHAIN_ID,
            targetChainId: TARGET_CHAIN_ID,
            flags: bytes32(uint(0x3F)),
            data: customExecutionData
        });

        paymentClient.exposed_addPaymentOrder(order);
        vm.prank(address(paymentClient));

        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        bytes32 intentId = bytes32(
            paymentProcessor.getBridgeDataByPaymentId(
                paymentProcessor.getPaymentId() - 1
            )
        );
        assertTrue(intentId != bytes32(0));
    }

    //--------------------------------------------------------------------------
    // Payment Order Validation Tests

    /* Test Function validPaymentOrder()
        └── Given a payment order with address(0) recipient
            └── When validating the payment order
                └── Then it should return false
    */
    function testValidPaymentOrder_revertsGivenInvalidRecipient() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0),
            paymentToken: address(_token),
            amount: 10 ether,
            originChainId: ORIGIN_CHAIN_ID,
            targetChainId: TARGET_CHAIN_ID,
            flags: bytes32(uint(0x3F)), // Binary: ...0011 1111
            data: _getExecutionData()
        });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test Function validPaymentOrder()
        └── Given a payment order with address(0) token
            └── When validating the payment order
                └── Then it should return false
    */
    function testValidPaymentOrder_revertsGivenInvalidToken() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(0),
            amount: 1,
            originChainId: ORIGIN_CHAIN_ID,
            targetChainId: TARGET_CHAIN_ID,
            flags: bytes32(uint(0x3F)), // Binary: ...0011 1111
            data: _getExecutionData()
        });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test Function validPaymentOrder()
        └── Given a payment order with zero amount
            └── When validating the payment order
                └── Then it should return false
    */
    function testValidPaymentOrder_revertsGivenInvalidAmount() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(_token),
            amount: 0,
            originChainId: ORIGIN_CHAIN_ID,
            targetChainId: TARGET_CHAIN_ID,
            flags: bytes32(uint(0x3F)), // Binary: ...0011 1111
            data: _getExecutionData()
        });
        assertEq(paymentProcessor.validPaymentOrder(order), false);
    }

    /* Test Function validPaymentOrder()
        └── Given a valid payment order
            └── When validating the payment order
                └── Then it should return true
    */
    function testValidPaymentOrder_succeedsGivenValidPaymentOrder() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0xBEEF),
            paymentToken: address(_token),
            amount: 10 ether,
            originChainId: ORIGIN_CHAIN_ID,
            targetChainId: TARGET_CHAIN_ID,
            flags: bytes32(uint(0x3F)), // Binary: ...0011 1111
            data: _getExecutionData()
        });
        assertEq(paymentProcessor.validPaymentOrder(order), true);
    }

    // ========================================================================
    // Test Internal

    /*   Test Function _processSuccessfulBridgeTransfer()
        └── When the function _processSuccessfulBridgeTransfer() is called
            ├── Then the function should emit events
            ├── And the function should store the paymentID to IntentID
            └── And the function should store the intent
    */
    function testInternalProcessSuccessfulBridgeTransfer_worksGivenValidData()
        public
    {
        // Create valid intent ID and intent
        (bytes32 intentId, IEverclear.Intent memory intent) =
            _getValidIntentIdAndIntent();
        // Create valid payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        _createTestPaymentOrder(
            address(paymentClient),
            10 ether,
            address(_token),
            _getExecutionData()
        );

        // pre-assertions
        assertEq(paymentProcessor.getPaymentId(), 0); // payment ID is 0
        // Payment ID 0 has no bridge data
        assertEq(paymentProcessor.getBridgeDataByPaymentId(0), bytes(""));
        // Payment ID 0 has no intent
        IEverclear.Intent memory preTestIntent =
            paymentProcessor.getIntentByIntentId(intentId);
        assertEq(
            preTestIntent.initiator,
            bytes32(uint(uint160(address(paymentProcessor))))
        );

        // Test function call and emit events
        vm.expectEmit(true, true, true, true);
        emit IPaymentProcessor_v1.PaymentOrderProcessed(
            address(paymentClient),
            order.recipient,
            order.paymentToken,
            order.amount,
            order.originChainId,
            order.targetChainId,
            order.flags,
            order.data
        );
        emit IPP_CrossChainBase_v1.BridgeTransferCompleted(
            paymentProcessor.getPaymentId(),
            intentId,
            order.recipient,
            address(paymentClient),
            order.paymentToken,
            order.amount,
            order.originChainId,
            order.targetChainId,
            order.flags,
            order.data
        );
        emit IPaymentProcessor_v1.TokensReleased(
            order.recipient, order.paymentToken, order.amount
        );
        paymentProcessor.exposed_processSuccessfulBridgeTransfer(
            order, address(paymentClient), intentId, intent
        );

        // post-assertions
        assertEq(paymentProcessor.getPaymentId(), 1);
        IEverclear.Intent memory postTestIntent =
            paymentProcessor.getIntentByIntentId(intentId);
        _assertValidIntent(postTestIntent, intent);
        assertEq(
            paymentProcessor.getBridgeDataByPaymentId(0),
            abi.encodePacked(intentId)
        );
    }

    /*   Test Function _processFailedBridgeTransfer()
        └── When the function _processFailedBridgeTransfer() is called
            ├── Then the function store the unclaimable amount
            └── And the function should emit and event
    */
    function testInternalProcessFailedBridgeTransfer_worksGivenValidData()
        public
    {
        // Create valid intent ID and intent
        (bytes32 intentId, IEverclear.Intent memory intent) =
            _getValidIntentIdAndIntent();
        // Create valid payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        _createTestPaymentOrder(
            address(paymentClient),
            10 ether,
            address(_token),
            _getExecutionData()
        );

        // pre-assertions
        assertEq(paymentProcessor.getPaymentId(), 0); // payment ID is 0
        // Payment ID 0 has no bridge data
        assertEq(paymentProcessor.getBridgeDataByPaymentId(0), bytes(""));
        // Payment ID 0 has no intent
        IEverclear.Intent memory preTestIntent =
            paymentProcessor.getIntentByIntentId(intentId);
        assertEq(
            preTestIntent.initiator,
            bytes32(uint(uint160(address(paymentProcessor))))
        );
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), order.paymentToken, order.recipient
            ),
            0
        );

        // Test function call and emit event
        vm.expectEmit(true, true, true, true);
        emit IPP_CrossChainBase_v1.BridgeTransferFailed(
            address(paymentClient),
            order.recipient,
            order.paymentToken,
            order.amount,
            order.originChainId,
            order.targetChainId,
            order.flags,
            order.data
        );
        paymentProcessor.exposed_processFailedBridgeTransfer(
            order, address(paymentClient)
        );

        // post-assertions
        assertEq(
            paymentProcessor.unclaimable(
                address(paymentClient), order.paymentToken, order.recipient
            ),
            order.amount
        );
    }

    /* Test exposed TTL and max fee extraction
        └── Given flags and data with valid TTL and max fee
            └── When getting TTL and max fee directly
                └── Then it should return correct values
    */
    function testInternalGetEverclearMaxFeeAndTTL_worksGivenValidData(
        uint24 maxFee_,
        uint48 ttl_
    ) public {
        vm.assume(maxFee_ > 0);
        vm.assume(ttl_ > 0);

        // Create test data array with known values
        bytes32[] memory testData = new bytes32[](6);
        testData[FLAG_MAX_FEE] = bytes32(uint(maxFee_));
        testData[FLAG_TTL] = bytes32(uint(ttl_));

        // Get values using exposed function
        (uint24 returnedMaxFee, uint48 returnedTtl) =
            paymentProcessor.exposed_getEverclearMaxFeeAndTTL(testData);

        // Verify returned values match inputs
        assertEq(returnedMaxFee, maxFee_);
        assertEq(returnedTtl, ttl_);
    }

    /* Test exposed TTL and max fee extraction with short array
        └── Given data array that's too short
            └── When getting TTL and max fee directly
                └── Then it should revert on array bounds
    */
    function testInternalGetEverclearMaxFeeAndTTL_revertsGivenShortArray()
        public
    {
        bytes32[] memory shortData = new bytes32[](2); // Too short array
        vm.expectRevert(); // Should revert when accessing out of bounds
        paymentProcessor.exposed_getEverclearMaxFeeAndTTL(shortData);
    }

    /* Test exposed chain ID validation with valid IDs
        └── Given origin as current chain and different target chain
            └── When validating chain IDs directly
                └── Then it should return true
    */
    function testInternalValidateOriginAndTargetChainId_worksGivenValidChainIdsReturnsTrue(
    ) public {
        bool isValid = paymentProcessor.exposed_validateOriginAndTargetChainId(
            block.chainid, // origin = current chain
            1337 // target = different chain
        );
        assertTrue(isValid);
    }

    /* Test exposed chain ID validation with wrong origin
        └── Given origin different from current chain
            └── When validating chain IDs directly
                └── Then it should return false
    */
    function testInternalValidateOriginAndTargetChainId_worksGivenWrongOriginReturnsFalse(
    ) public {
        bool isValid = paymentProcessor.exposed_validateOriginAndTargetChainId(
            1337, // origin = wrong chain
            block.chainid // target = current chain
        );
        assertFalse(isValid);
    }

    /* Test exposed chain ID validation with same chains
        └── Given target same as current chain
            └── When validating chain IDs directly
                └── Then it should return false
    */
    function testInternalValidateOriginAndTargetChainId_woksGivenSameChainsReturnsFalse(
    ) public {
        bool isValid = paymentProcessor.exposed_validateOriginAndTargetChainId(
            block.chainid, // origin = current chain
            block.chainid // target = same as current (invalid)
        );
        assertFalse(isValid);
    }

    /* Test exposed flags validation with valid data
        └── Given flags with MAX_FEE and TTL set and matching data length
            └── When validating flags and data directly
                └── Then it should return true
    */
    function testInternalValidateFlagsAndData_worksGivenValidDataReturnsTrue()
        public
    {
        // 0x3F = ...0011 1111 - has both MAX_FEE and TTL flags set
        bytes32 flags = bytes32(uint(0x3F));
        bytes32[] memory data = new bytes32[](6); // 6 flags are set in 0x3F

        bool isValid =
            paymentProcessor.exposed_validateFlagsAndData(flags, data);
        assertTrue(isValid);
    }

    /* Test exposed flags validation with missing required flags
        └── Given flags without MAX_FEE or TTL set
            └── When validating flags and data directly
                └── Then it should return false
    */
    function testInternalValidateFlagsAndData_worksGivenMissingRequiredFlagsReturnsFalse(
    ) public {
        // 0x03 = ...0000 0011 - missing both MAX_FEE and TTL flags
        bytes32 flags = bytes32(uint(0x03));
        bytes32[] memory data = new bytes32[](2);

        bool isValid =
            paymentProcessor.exposed_validateFlagsAndData(flags, data);
        assertFalse(isValid);
    }

    /* Test exposed flags validation with mismatched data length
        └── Given flags and data array with mismatched length
            └── When validating flags and data directly
                └── Then it should return false
    */
    function testInternalValidateFlagsAndData_worksGivenMismatchedLengthReturnsFalse(
    ) public {
        // 0x3F = ...0011 1111 - has 6 flags set
        bytes32 flags = bytes32(uint(0x3F));
        bytes32[] memory data = new bytes32[](3); // Wrong length, should be 6

        bool isValid =
            paymentProcessor.exposed_validateFlagsAndData(flags, data);
        assertFalse(isValid);
    }

    /* Test Function _validPaymentOrder() comprehensively
        └── Given a payment order with various configurations
            └── When validating the payment order
                ├── Then it should return true for valid orders
                └── And it should return false for invalid orders
    */
    function testInternalValidPaymentOrder_worksGivenValidPaymentOrder()
        public
    {
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        _createTestPaymentOrder(
            address(0xBEEF), 10 ether, address(_token), _getExecutionData()
        );
        assertEq(paymentProcessor.validPaymentOrder(order), true);
    }

    /* Test Function _executeBridgeTransfer()
        └── Given a valid payment order
            └── When the bridge transfer fails
                ├── Then the unclaimable amount should be set correctly
                └── And the payment processor should handle the failure gracefully
    */
    function testInternalExecuteBridgeTransfer_revertsGivenInvalidData()
        public
    {
        // Setup: Create a valid payment order
        address testRecipient = address(0xBEEF);
        uint testAmount = 10 ether;
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup: Mint tokens to payment processor and approve
        vm.prank(address(paymentProcessor));
        _token.mint(address(paymentProcessor), testAmount);
        vm.prank(address(paymentProcessor));
        _token.approve(address(everclearPaymentMock), testAmount);

        // Setup: Set mock bridge to fail
        everclearPaymentMock.setMockBridgeToFail(true);

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        _createTestPaymentOrder(
            testRecipient, testAmount, address(_token), _getExecutionData()
        );

        // Call executeBridgeTransfer with invalid data
        paymentProcessor.exposed_executeBridgeTransfer(order);

        // Check unclaimable amount with the correct client address
        assertEq(
            paymentProcessor.unclaimable(
                address(this), // Use the test contract address as the client
                address(_token),
                testRecipient
            ),
            testAmount
        );
    }

    /* Test Function _createCrossChainIntent()
        └── Given a valid payment order
            └── When creating a cross-chain intent
                ├── Then it should return a valid intent ID
                ├── And it should create an intent with the correct parameters
                └── And it should store the intent in the payment processor
    */
    function testInternalCreateCrossChainIntent_worksGivenValidData() public {
        // Setup: Create a valid payment order
        address testRecipient = address(0xBEEF);
        uint testAmount = 10 ether;
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup: Mint tokens to payment processor and approve
        vm.prank(address(paymentProcessor));
        _token.mint(address(paymentProcessor), testAmount);
        vm.prank(address(paymentProcessor));
        _token.approve(address(everclearPaymentMock), testAmount);

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        _createTestPaymentOrder(
            testRecipient, testAmount, address(_token), _getExecutionData()
        );

        // Call createCrossChainIntent with valid data
        (bytes32 intentId, IEverclear.Intent memory intent) =
            paymentProcessor.exposed_createCrossChainIntent(order);

        // Post-assertions
        assert(intentId != bytes32(0));
        assertEq(
            intent.initiator, bytes32(uint(uint160(address(paymentProcessor))))
        );
    }

    /* Test Function _transferTokenAndApproveToBridge()
        └── Given a valid payment order and client
            └── When transferring tokens to the bridge
                ├── Then the tokens should be transferred from the client to the payment processor
                ├── And the payment processor should approve the bridge to spend the tokens
                └── And the payment processor should have the correct token balance
    */
    function testInternalTransferTokenAndApproveToBridge_worksGivenValidData()
        public
    {
        // Setup: Create a valid payment order
        address testRecipient = address(0xBEEF);
        uint testAmount = 10 ether;
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup: Mint tokens to the client
        _token.mint(address(paymentClient), testAmount);

        // Setup: Approve the payment processor to spend the client's tokens
        vm.prank(address(paymentClient));
        _token.approve(address(paymentProcessor), testAmount);

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        _createTestPaymentOrder(
            testRecipient, testAmount, address(_token), _getExecutionData()
        );

        // Add the payment order to the client to set up its internal state
        paymentClient.exposed_addPaymentOrder(order);

        // Record initial balances
        uint initialProcessorBalance =
            _token.balanceOf(address(paymentProcessor));
        uint initialClientBalance = _token.balanceOf(address(paymentClient));
        vm.prank(address(paymentClient));
        // Call the function to be tested
        paymentProcessor.exposed_transferTokenAndApproveToBridge(
            order, address(paymentClient)
        );

        // Post-assertions
        // Check that tokens were transferred from client to processor
        assertEq(
            _token.balanceOf(address(paymentProcessor)),
            initialProcessorBalance + testAmount
        );
        assertEq(
            _token.balanceOf(address(paymentClient)),
            initialClientBalance - testAmount
        );

        // Check that the processor approved the bridge to spend the tokens
        assertEq(
            _token.allowance(
                address(paymentProcessor), address(everclearPaymentMock)
            ),
            testAmount
        );
    }

    // @todo internal functions to test:
    // _validPaymentOrder: Would test at the end of testing all the other internal functions it calls
    // _executeBridgeTransfer: Main point to test here is the if/else logic. Maybe this can be done with
    //      an invalid everclear mock which returns a 0 intentId.
    // _transferTokenAndApproveToBridge: Should be straightforward.
    //      We just need to set the open amount in the payment client and mint tokens to it so it can be transferred.
    // _createCrossChainIntent: Not a lot we can test here. Maybe use the same mock data to be returned as I've
    //      setup below in this test file.

    // ========================================================================
    // Helper functions

    function _assertValidIntent(
        IEverclear.Intent memory intentToBeTested_,
        IEverclear.Intent memory intentToBeExpectedValues_
    ) internal {
        assertEq(
            intentToBeTested_.initiator, intentToBeExpectedValues_.initiator
        );
        assertEq(intentToBeTested_.receiver, intentToBeExpectedValues_.receiver);
        assertEq(
            intentToBeTested_.inputAsset, intentToBeExpectedValues_.inputAsset
        );
        assertEq(
            intentToBeTested_.outputAsset, intentToBeExpectedValues_.outputAsset
        );
        assertEq(intentToBeTested_.amount, intentToBeExpectedValues_.amount);
        assertEq(intentToBeTested_.maxFee, intentToBeExpectedValues_.maxFee);
        assertEq(intentToBeTested_.origin, intentToBeExpectedValues_.origin);
        assertEq(intentToBeTested_.nonce, intentToBeExpectedValues_.nonce);
        assertEq(
            intentToBeTested_.timestamp, intentToBeExpectedValues_.timestamp
        );
        assertEq(intentToBeTested_.ttl, intentToBeExpectedValues_.ttl);
    }

    function _setupSinglePayment(
        address recipient_,
        uint amount_,
        bytes32[] memory executionData_
    ) internal returns (IERC20PaymentClientBase_v2.PaymentOrder[] memory) {
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = recipient_;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = amount_;

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
        _createPaymentOrders(1, setupRecipients, setupAmounts, executionData_);
        return orders;
    }

    function _createPaymentOrders(
        uint orderCount,
        address[] memory recipients,
        uint[] memory amounts,
        bytes32[] memory executionData
    ) internal returns (IERC20PaymentClientBase_v2.PaymentOrder[] memory) {
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            new IERC20PaymentClientBase_v2.PaymentOrder[](orderCount);

        for (uint i = 0; i < orderCount; i++) {
            orders[i] = _createTestPaymentOrder(
                recipients[i], amounts[i], address(_token), executionData
            );
            paymentProcessor.validPaymentOrder(orders[i]);

            //add payment order to client
            paymentClient.exposed_addPaymentOrder(orders[i]);
        }
        return orders;
    }

    function _createTestPaymentOrder(
        address recipient,
        uint amount,
        address token,
        bytes32[] memory executionData
    ) internal view returns (IERC20PaymentClientBase_v2.PaymentOrder memory) {
        bytes32[] memory data = new bytes32[](6);

        if (executionData.length == 6 && executionData[0] == bytes32(0)) {
            data = _getExecutionData();
        } else {
            data = executionData;
        }

        return IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient,
            paymentToken: token,
            amount: amount,
            originChainId: ORIGIN_CHAIN_ID,
            targetChainId: TARGET_CHAIN_ID,
            flags: bytes32(uint(0x3F)), // Binary: ...0011 1111
            data: data
        });
    }

    function _assumeValidRecipientAndAmount(
        address testRecipient,
        uint testAmount
    ) internal view {
        vm.assume(testRecipient != address(0));
        vm.assume(testRecipient != address(msg.sender));
        vm.assume(testRecipient != address(this));

        vm.assume(testRecipient != address(paymentProcessor));
        vm.assume(testRecipient != address(paymentClient));
        vm.assume(testRecipient != address(_token));

        vm.assume(testRecipient != address(paymentProcessor.orchestrator()));
        vm.assume(
            testRecipient
                != address(paymentProcessor.orchestrator().fundingManager().token())
        );

        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY);
    }

    function _getExecutionData() internal view returns (bytes32[] memory) {
        // Pre-allocate with fixed size
        bytes32[] memory executionData = new bytes32[](6);

        // Use unchecked for gas optimization where overflow is impossible
        unchecked {
            executionData[0] = bytes32(uint(444));
            executionData[1] = bytes32(block.timestamp);
            executionData[2] = bytes32(uint(0));
            executionData[3] = bytes32(block.timestamp + 7 days);
            executionData[4] = bytes32(uint(1)); // maxFee
            executionData[5] = bytes32(uint(1)); // ttl
        }
        return executionData;
    }

    function _getValidIntentIdAndIntent()
        internal
        pure
        returns (bytes32 intentId_, IEverclear.Intent memory intent_)
    {
        uint32[] memory destinations = new uint32[](1);
        destinations[0] = 11_155_420;

        // Data copied from a real intent from Everclear
        intent_ = IEverclear.Intent({
            initiator: bytes32(
                uint(uint160(0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0))
            ),
            receiver: bytes32(
                uint(uint160(0xDDDeAfB492752FC64220ddB3E7C9f1d5CcCdFdF0))
            ),
            inputAsset: bytes32(
                uint(uint160(0xd26e3540A0A368845B234736A0700E0a5A821bBA))
            ),
            outputAsset: bytes32(
                uint(uint160(0x7Fa13D6CB44164ea09dF8BCc673A8849092D435b))
            ),
            amount: 1_000_000_000_000_000_000,
            maxFee: 0,
            origin: 11_155_111,
            nonce: 43,
            destinations: destinations,
            timestamp: 1_743_502_212,
            ttl: 0,
            data: "0x"
        });

        intentId_ = bytes32(
            uint(
                0xf361098677e612fef4f093113fb308e2e8eb3ff0815756a90acb3ae98fea827c
            )
        );
    }
}
