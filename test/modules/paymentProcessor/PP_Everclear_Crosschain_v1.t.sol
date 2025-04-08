// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

//--------------------------------------------------------------------------
// Imports
// External Dependencies

import {Clones} from "@oz/proxy/Clones.sol";
import {IWETH} from "@pp/interfaces/IWETH.sol";
import "forge-std/console2.sol";

// Internal Dependencies
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IPP_CrossChainBase_v1} from "@pp/interfaces/IPP_CrossChainBase_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IPP_Everclear_CrossChain_v1} from
    "@pp/interfaces/IPP_Everclear_CrossChain_v1.sol";

// Tests and Mocks
import {PP_Everclear_CrossChain_v1_Exposed} from
    "test/modules/paymentProcessor/PP_Everclear_CrossChain_v1_Exposed.sol";
import {EverclearPaymentMock} from
    "test/utils/mocks/external/EverclearPaymentMock.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_Everclear_CrossChain_v1_Test is ModuleTest {
    // ============================================================================
    // Constants

    uint constant MINTED_SUPPLY = 1000 ether;
    uint constant ZERO_AMOUNT = 0;

    // ============================================================================
    // State

    PP_Everclear_CrossChain_v1_Exposed public paymentProcessor;
    EverclearPaymentMock public everclearPaymentMock;
    ERC20PaymentClientBaseV2Mock paymentClient;
    IPP_CrossChainBase_v1 public CrossChainBase;
    IWETH public weth;

    // Bridge-related storage
    address public mockConnextBridge;
    address public mockEverClearSpoke;
    address public mockWeth;

    // Chain IDs
    uint ORIGIN_CHAIN_ID;
    uint TARGET_CHAIN_ID;

    // Execution data storage
    bytes32[] public EMPTY_EXECUTION_DATA = new bytes32[](6);
    uint maxFee = 0;
    uint ttl = 1;
    uint FLAG_MAX_FEE = 4;
    uint FLAG_TTL = 5;

    // ============================================================================
    // Setup
    function setUp() public {
        // Deploy mock contracts and set addresses
        everclearPaymentMock = new EverclearPaymentMock();
        mockEverClearSpoke = address(everclearPaymentMock);
        mockWeth = address(weth); // @note what is being set here?

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
        bytes memory configData = abi.encode(mockEverClearSpoke, mockWeth);
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

    // ============================================================================
    // Test Init & SupportsInterface

    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.getEverClearSpoke()), mockEverClearSpoke
        );
        assertEq(address(paymentProcessor.getWeth()), mockWeth);
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

    //--------------------------------------------------------------------------
    // Payment Processing Tests

    /* Test single payment processing
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
        console2.log(
            "balance of mockEverClearSpoke",
            _token.balanceOf(address(mockEverClearSpoke))
        );

        bytes32 intentId = bytes32(paymentProcessor.getBridgeData(0));
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(EverclearPaymentMock.IntentStatus.ADDED)
        );
        console2.logBytes32(intentId);
    }

    /* Test single payment outstanding token amounts
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

    /* Test multiple payment processing
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

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
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
            bytes32 intentId = bytes32(paymentProcessor.getBridgeData(i));
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

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
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
        // Process payments and verify _bridgeData mapping is not updated
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) == keccak256(bytes("")),
            "Bridge data should be empty"
        );
        assertEq(
            bytes32(
                paymentProcessor.getBridgeData(paymentProcessor.getPaymentId())
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
        ├── Given empty execution data bytes
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidExecutionData
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
        ├── Given a payment order with address(0) recipient
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidRecipient
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
        ├── Given a payment order with zero amount
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidAmount
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
        ├── Given a valid payment order
        │   └── When processing payment
        │       └── Then bridge data should not be empty
        │           └── And intent ID should be stored correctly
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
        // Process payments and verify _bridgeData mapping is updated
        paymentProcessor.processPayments(client);
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) != keccak256(bytes("")),
            "Bridge data should not be empty"
        );

        bytes32 intentId = bytes32(paymentProcessor.getBridgeData(0));
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(EverclearPaymentMock.IntentStatus.ADDED)
        );
    }

    /* Test empty bridge data
        ── When checking bridge data with no added payments
            └── Then it should return empty bytes
    */
    function testProcessPayments_succeedsGivenEmptyBridgeData() public {
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        // Process payments and verify _bridgeData mapping is updated
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(client);
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) == keccak256(bytes("")),
            "Bridge data should be empty"
        );
    }

    /* Test edge case amounts
        └── Given payment processor has exactly required amount
            └── When processing payment
                └── Then it should process successfully
                    └── And should emit PaymentProcessed event
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

    /* Test retry failed transfer
    └── Given a failed transfer
        └── When retrying with valid execution data
            └── Then it should create a new intent
                └── And clear the failed transfer record
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
            paymentProcessor.getBridgeData(paymentProcessor.getPaymentId() - 1)
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
                paymentProcessor.getBridgeData(paymentProcessor.getPaymentId())
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

        bytes32 pendingIntentId = bytes32(
            paymentProcessor.getBridgeData(paymentProcessor.getPaymentId())
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
            └── Then it should revert with NothingToClaim
                └── And the intent ID should remain unchanged
                └── And the payment order should remain processed
    */
    function testClaimUnclaimable_revertsGivenProcessedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment and process it
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
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

    /* Test retry with no failed transfer record
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

    /* Test retry with existing intent
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
        └── Then it should handle duplicates correctly
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

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _createPaymentOrders(3, recipients, amounts, EMPTY_EXECUTION_DATA);
        vm.prank(address(paymentClient));
        // Process payments
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Verify final intent ID exists
        bytes32 finalIntentId = bytes32(
            paymentProcessor.getBridgeData(paymentProcessor.getPaymentId() - 1)
        );
        assertTrue(finalIntentId != bytes32(0));
    }

    /* Test payment processing with varying start/end times
    └── Given payment orders with different time configurations
    └── When processing payments
        └── Then it should handle valid time ranges
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
            paymentProcessor.getBridgeData(paymentProcessor.getPaymentId() - 1)
        );
        assertTrue(intentId != bytes32(0));
    }

    //--------------------------------------------------------------------------
    // Payment Order Validation Tests

    /* Test invalid recipient
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

    /* Test invalid token
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

    /* Test invalid amount
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

    /* Test valid payment order
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

    /* Test exposed TTL and max fee extraction
    └── Given flags and data with valid TTL and max fee
        └── When getting TTL and max fee directly
            └── Then it should return correct values
    */
    function testExposed_getEverclearMaxFeeAndTTL_succeedsGivenValidData(
        uint24 maxFee,
        uint48 ttl
    ) public {
        vm.assume(maxFee > 0);
        vm.assume(ttl > 0);

        // Create test data array with known values
        bytes32[] memory testData = new bytes32[](6);
        testData[FLAG_MAX_FEE] = bytes32(uint(maxFee));
        testData[FLAG_TTL] = bytes32(uint(ttl));

        // Get values using exposed function
        (uint24 returnedMaxFee, uint48 returnedTtl) = paymentProcessor
            .exposed_getEverclearMaxFeeAndTTL(bytes32(uint(0x3F)), testData);

        // Verify returned values match inputs
        assertEq(returnedMaxFee, maxFee);
        assertEq(returnedTtl, ttl);
    }

    /* Test exposed TTL and max fee extraction with short array
    └── Given data array that's too short
        └── When getting TTL and max fee directly
            └── Then it should revert on array bounds
    */
    function testExposed_getEverclearMaxFeeAndTTL_revertsGivenShortArray()
        public
    {
        bytes32[] memory shortData = new bytes32[](2); // Too short array
        vm.expectRevert(); // Should revert when accessing out of bounds
        paymentProcessor.exposed_getEverclearMaxFeeAndTTL(
            bytes32(uint(0x3F)), shortData
        );
    }

    /* Test exposed chain ID validation with valid IDs
    └── Given origin as current chain and different target chain
        └── When validating chain IDs directly
            └── Then it should return true
    */
    function testExposed_validateOriginAndTargetChainId_succeedsGivenValidChainIds(
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
    function testExposed_validateOriginAndTargetChainId_failsGivenWrongOrigin()
        public
    {
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
    function testExposed_validateOriginAndTargetChainId_failsGivenSameChains()
        public
    {
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
    function testExposed_validateFlagsAndData_succeedsGivenValidData() public {
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
    function testExposed_validateFlagsAndData_failsGivenMissingRequiredFlags()
        public
    {
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
    function testExposed_validateFlagsAndData_failsGivenMismatchedLength()
        public
    {
        // 0x3F = ...0011 1111 - has 6 flags set
        bytes32 flags = bytes32(uint(0x3F));
        bytes32[] memory data = new bytes32[](3); // Wrong length, should be 6

        bool isValid =
            paymentProcessor.exposed_validateFlagsAndData(flags, data);
        assertFalse(isValid);
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function _setupSinglePayment(
        address _recipient,
        uint _amount,
        bytes32[] memory executionData
    ) internal returns (IERC20PaymentClientBase_v2.PaymentOrder[] memory) {
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = _recipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = _amount;

        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
        _createPaymentOrders(1, setupRecipients, setupAmounts, executionData);
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
            bool isValid = paymentProcessor.validPaymentOrder(orders[i]);
            console2.log("isValid", isValid);
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
}
