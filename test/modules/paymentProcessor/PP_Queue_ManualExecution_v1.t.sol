// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
import {
    PP_Simple_v1,
    IPaymentProcessor_v1
} from "src/modules/paymentProcessor/PP_Simple_v1.sol";

// External
import {Test} from "forge-std/Test.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

// Tests and Mocks
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {PP_Queue_v1_Exposed} from
    "test/modules/paymentProcessor/utils/mocks/PP_Queue_v1_Exposed.sol";
import {PP_Simple_v1AccessMock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Simple_v1AccessMock.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {NonStandardTokenMock} from
    "test/utils/mocks/token/NonStandardTokenMock.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// System under testing
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {PP_Queue_ManualExecution_v1} from "@pp/PP_Queue_ManualExecution_v1.sol";
import {PP_Queue_ManualExecution_v1_Exposed} from
    "test/modules/paymentProcessor/utils/mocks/PP_Queue_ManualExecution_v1_Exposed.sol";
import {PP_Queue_v1_Test} from "./PP_Queue_v1.t.sol";

contract PP_Queue_ManualExecution_v1_Test is PP_Queue_v1_Test {
    // SuT
    PP_Queue_ManualExecution_v1_Exposed queueManualExecution;

    function init() public {
        address impl = address(new PP_Queue_ManualExecution_v1_Exposed());
        queueManualExecution =
            PP_Queue_ManualExecution_v1_Exposed(Clones.clone(impl));

        // Setup orchestrator once
        _setUpOrchestrator(queueManualExecution);
        _authorizer.setIsAuthorized(address(this), true);

        // Initialize queue manual execution
        queueManualExecution.init(
            _orchestrator,
            _METADATA,
            abi.encode(canceledOrdersTreasury, failedOrdersTreasury)
        );

        // Setup payment client
        impl = address(new ERC20PaymentClientBaseV2Mock());
        paymentClient = ERC20PaymentClientBaseV2Mock(Clones.clone(impl));

        // Register payment client as module in the same orchestrator
        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));

        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(queueManualExecution), true);
        paymentClient.setToken(_token);
    }

    /* Test testPublicProcessPayments_succeedsGivenValidSetupAndPaymentOrder() function
    ├── Given a valid payment setup
    │   └── And a payment order has been queued
    │       └── When processPayments is called
    │           └── Then the order should be added to the queue correctly
    │           └── And no tokens should be transferred yet
    │           └── And attempting to remove a non-existent order should revert
    │           └── And removing the actual order should succeed
    */
    function testPublicProcessPayments_succeedsGivenValidSetupAndPaymentOrderInManualExecution(
    ) public {
        init();
        // Setup payment client with orders
        address recipient = makeAddr("recipient");
        address paymentToken = address(_token);
        uint amount = 1000;
        uint originChainId = block.chainid;
        uint targetChainId = block.chainid;

        (bytes32 flags_, bytes32[] memory data_) =
            helper_encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory orders =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: paymentToken,
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: flags_,
            data: data_
        });

        // Setup initial state
        _token.mint(address(paymentClient), amount);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queueManualExecution), amount);

        // Add payment order to queue
        uint orderId_ = queueManualExecution.exposed_addPaymentOrderToQueue(
            orders, address(paymentClient)
        );
        vm.stopPrank();

        // Call processPayments as the module to add to queue
        vm.prank(address(paymentClient));
        queueManualExecution.processPayments(paymentClient);

        // Verify order was added correctly to the queue
        assertEq(orderId_, 1, "Order ID should be 1");

        // Verify no tokens were transferred yet (they are transferred on executePaymentQueue)
        assertEq(
            _token.balanceOf(address(queueManualExecution)),
            0,
            "Queue should not have tokens yet"
        );
        assertEq(
            _token.balanceOf(address(paymentClient)),
            amount,
            "Payment client should still have tokens"
        );

        // Try to remove non-existent order - should revert
        vm.expectRevert();
        queueManualExecution.exposed_removeFromQueue(
            orderId_ + 1, address(paymentClient)
        );

        // Remove the actual order
        queueManualExecution.exposed_removeFromQueue(
            orderId_, address(paymentClient)
        );
    }

    /* Test testPublicProcessPayments_failsGivenUnregisteredClient() function
        ├── Given an unregistered payment client
        │   └── When processPayments is called with this client
        │       └── Then the transaction should revert with "Module__PP_Queue_OnlyCallableByClient()"
    */
    function testPublicProcessPayments_failsGivenUnregisteredClient() public {
        init();
        // Create another payment client that is not registered
        ERC20PaymentClientBaseV2Mock otherPaymentClient =
            new ERC20PaymentClientBaseV2Mock();

        // Try to call processPayments with unregistered client
        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_OnlyCallableByClient()")
        );
        queueManualExecution.processPayments(otherPaymentClient);
    }

    /* Test testPublicExecutePaymentQueue_succeedsGivenValidOrderAndSetup() function
        ├── Given a valid payment order setup and queued
        │   └── When executePaymentQueue is called
        │       └── Then the payment should be processed successfully
        │       └── And the recipient should receive the tokens
        │       └── And the queue should have no tokens left
        │       └── And the payment client should have no tokens left
    */
    function testPublicExecutePaymentQueue_succeedsGivenValidOrderAndSetup()
        public
    {
        init();
        // Setup payment client and token
        address recipient = makeAddr("recipient");
        address paymentToken = address(_token);
        uint amount = 1000;
        uint originChainId = block.chainid;
        uint targetChainId = block.chainid;

        (bytes32 flags_, bytes32[] memory data_) =
            helper_encodePaymentOrderData(1);

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: paymentToken,
            originChainId: originChainId,
            targetChainId: targetChainId,
            flags: flags_,
            data: data_
        });

        // Setup token balances and approvals
        _token.mint(address(paymentClient), amount);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queueManualExecution), amount);

        // Add order to queue
        uint orderId = queueManualExecution.exposed_addPaymentOrderToQueue(
            order, address(paymentClient)
        );
        vm.stopPrank();

        assertGt(orderId, 0, "Order should be added with valid ID");

        // Call executePaymentQueue from the payment client (which is a module)
        vm.prank(address(paymentClient));
        queueManualExecution.executePaymentQueue(paymentClient);

        // Verify final state
        assertEq(
            _token.balanceOf(recipient),
            amount,
            "Recipient should receive tokens"
        );
        assertEq(
            _token.balanceOf(address(queueManualExecution)),
            0,
            "Queue should have no tokens"
        );
        assertEq(
            _token.balanceOf(address(paymentClient)),
            0,
            "Payment client should have no tokens"
        );
    }
}
