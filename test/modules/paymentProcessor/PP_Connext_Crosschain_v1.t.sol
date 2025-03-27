// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

//--------------------------------------------------------------------------
// Imports
// External Dependencies

import {Clones} from "@oz/proxy/Clones.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import "forge-std/console2.sol";

// Internal Dependencies
import {ICrossChainBase_v1} from "@pp/interfaces/ICrossChainBase_v1.sol";
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IPP_CrossChain_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_CrossChain_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IPP_Connext_CrossChain_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_Connext_CrossChain_v1.sol";

// Tests and Mocks
import {PP_Connext_CrossChain_v1_Exposed} from
    "test/utils/mocks/modules/paymentProcessor/PP_Connext_CrossChain_v1_Exposed.sol";
import {Mock_EverclearPayment} from
    "test/utils/mocks/external/Mock_EverclearPayment.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_Connext_CrossChain_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    // Constants
    uint constant MINTED_SUPPLY = 1000 ether;
    uint constant ZERO_AMOUNT = 0;
    uint ORIGIN_CHAIN_ID;
    uint TARGET_CHAIN_ID;
    //--------------------------------------------------------------------------
    // Test Storage
    PP_Connext_CrossChain_v1_Exposed public paymentProcessor;
    Mock_EverclearPayment public everclearPaymentMock;
    ERC20PaymentClientBaseV2Mock paymentClient;
    IPP_CrossChain_v1 public CrossChainBase;
    IWETH public weth;

    // Bridge-related storage
    address public mockConnextBridge;
    address public mockEverClearSpoke;
    address public mockWeth;

    // Execution data storage
    uint maxFee = 0;
    uint ttl = 1;
    bytes32[] public emptyExecutionData;

    //--------------------------------------------------------------------------
    // Setup Function

    function setUp() public {
        // Deploy mock contracts and set addresses
        everclearPaymentMock = new Mock_EverclearPayment();
        mockEverClearSpoke = address(everclearPaymentMock);
        mockWeth = address(weth);

        // Deploy payment processor via clone
        address impl = address(new PP_Connext_CrossChain_v1_Exposed());
        paymentProcessor = PP_Connext_CrossChain_v1_Exposed(Clones.clone(impl));

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

        ORIGIN_CHAIN_ID = block.chainid;
        TARGET_CHAIN_ID = 1337;

        emptyExecutionData = new bytes32[](6);
    }

    //--------------------------------------------------------------------------
    // Initialization Tests

    /* Test initialization
    */
    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.getEverClearSpoke()), mockEverClearSpoke
        );
        assertEq(address(paymentProcessor.getWeth()), mockWeth);
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
        // Test for IPP_Connext_CrossChain_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPP_Connext_CrossChain_v1).interfaceId
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
    function testProcessPayments_worksGivenSingleValidPaymentOrder(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);
        _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

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
            uint(Mock_EverclearPayment.IntentStatus.ADDED)
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
        _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);
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
            numRecipients, setupRecipients, setupAmounts, emptyExecutionData
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

        // Process payments
        paymentProcessor.processPayments(client);

        uint totalAmount = 0;
        //should be checking in the mock for valid bridge data
        for (uint i = 0; i < numRecipients; i++) {
            bytes32 intentId = bytes32(paymentProcessor.getBridgeData(i));
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
            numRecipients, setupRecipients, setupAmounts, emptyExecutionData
        );

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

    function testProcessPayments_succeedsGivenNoPaymentOrders() public {
        // Process payments and verify _bridgeData mapping is not updated
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
        vm.expectRevert();
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

        _setupSinglePayment(address(0), testAmount, emptyExecutionData);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        // Process payments
        vm.expectRevert(
            IERC20PaymentClientBase_v2
                .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                .selector
        );
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

        _setupSinglePayment(testRecipient, 0, emptyExecutionData);
        // Get the client interface
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));

        // Process payments
        vm.expectRevert(
            IERC20PaymentClientBase_v2
                .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                .selector
        );
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
        _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);
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
    function testProcessPayments_succeedsGivenEmptyBridgeData() public {
        IERC20PaymentClientBase_v2 client =
            IERC20PaymentClientBase_v2(address(paymentClient));
        // Process payments and verify _bridgeData mapping is updated
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
        _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

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

    function testRetryFailedTransfer_succeedsGivenValidFailedTransfer(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup initial payment
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

        // First attempt with high maxFee to force failure
        everclearPaymentMock.setMockBridgeToFail(true);
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );
        console2.log(
            "paymentProcessor.unclaimable(address(paymentClient), address(_token), testRecipient)",
            paymentProcessor.unclaimable(
                address(paymentClient), address(_token), testRecipient
            )
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
            _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

        uint balanceBefore = _token.balanceOf(address(paymentProcessor));
        everclearPaymentMock.setMockBridgeToFail(true); //Force the bridge transfer to fail
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
        _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

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
            _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

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

        vm.expectRevert();
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
            _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

        vm.prank(address(paymentClient));
        vm.expectRevert(
            IPP_CrossChain_v1
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
            _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

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
    function testRetryFailedTransfer_revertsGivenInvalidExecutionData(
        address testRecipient,
        uint testAmount
    ) public {
        _assumeValidRecipientAndAmount(testRecipient, testAmount);

        // Setup failed transfer
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders =
            _setupSinglePayment(testRecipient, testAmount, emptyExecutionData);

        everclearPaymentMock.setMockBridgeToFail(true); //Force the bridge transfer to fail
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v2(address(paymentClient))
        );

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPP_CrossChain_v1
                    .Module__PP_CrossChain__MessageDeliveryFailed
                    .selector,
                ORIGIN_CHAIN_ID,
                TARGET_CHAIN_ID,
                orders[0].flags,
                orders[0].data
            )
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
            _createPaymentOrders(3, recipients, amounts, emptyExecutionData);

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
