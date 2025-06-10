// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";
import {IPaymentProcessor_v2} from "@pp/IPaymentProcessor_v2.sol";

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
} from "@unitTest/modules/ModuleTest.sol";
import {PP_Queue_v1_Exposed} from
    "@mocks/modules/paymentProcessor/PP_Queue_v1_Exposed.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {NonStandardTokenMock} from
    "@mocks/external/token/NonStandardTokenMock.sol";
import {OZErrors} from "@testUtilities/OZErrors.sol";

// System under testing
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";

contract PP_Queue_v1_Test is ModuleTest {
    // ================================================================================
    // Storage

    // SuT
    PP_Queue_v1_Exposed queue;

    // Mocks
    ERC20PaymentClientBaseV2Mock paymentClient;

    // ================================================================================
    // Events

    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );
    event UnclaimableAmountAdded(
        address indexed paymentClient,
        address indexed token,
        address indexed recipient,
        uint amount
    );

    // ================================================================================
    // Variables

    bytes32 public constant QUEUE_OPERATOR_ROLE = "QUEUE_OPERATOR_ROLE";
    // processPayments function selector
    bytes4 internal constant PROCESS_PAYMENTS_FUNCTION_SELECTOR =
        bytes4(keccak256(bytes("processPayments(address)")));
    uint internal constant BPS = 10_000;
    uint internal constant DEFAULT_MAX_ORDERS_PER_EXECUTION = 30;

    //Role
    bytes32 internal roleIDqueue;

    //Address
    address canceledOrdersTreasury;
    address failedOrdersTreasury;

    // ================================================================================
    // Setup

    function setUp() public {
        canceledOrdersTreasury = makeAddr("canceledOrdersTreasury");
        failedOrdersTreasury = makeAddr("failedOrdersTreasury");

        address impl = address(new PP_Queue_v1_Exposed());
        queue = PP_Queue_v1_Exposed(Clones.clone(impl));

        impl = address(new ERC20PaymentClientBaseV2Mock());
        paymentClient = ERC20PaymentClientBaseV2Mock(Clones.clone(impl));

        _setUpOrchestrator(paymentClient);
        // initiate SuT
        queue.init(
            _orchestrator,
            _METADATA,
            abi.encode(canceledOrdersTreasury, failedOrdersTreasury)
        );

        // Initiate mock payment client used for testing
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(queue), true);
        paymentClient.setToken(_token);

        // Turn on all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(true);
    }

    // ================================================================================
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(queue.orchestrator()), address(_orchestrator));
        assertEq(
            address(queue.getCanceledOrdersTreasury()),
            address(canceledOrdersTreasury)
        );
        assertEq(
            address(queue.getFailedOrdersTreasury()),
            address(failedOrdersTreasury)
        );
        assertEq(
            queue.getMaxOrdersPerExecution(), DEFAULT_MAX_ORDERS_PER_EXECUTION
        );
    }

    function testSupportsInterface() public override(ModuleTest) {
        assertTrue(
            queue.supportsInterface(type(IPaymentProcessor_v2).interfaceId)
        );
        assertTrue(queue.supportsInterface(type(IPP_Queue_v1).interfaceId));
        assertTrue(queue.supportsInterface(type(IERC165).interfaceId));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        queue.init(_orchestrator, _METADATA, bytes(""));
    }

    // ================================================================================
    // Test Queue Operations

    /* Test testQueueOperations_GivenValidRecipientAndAmount()
        └── Given a valid recipient and amount
            └── When adding a payment order to the queue
                ├── Then the order should be added successfully
                ├── Then the queue size should be incremented
                ├── Then the queued order amount should match input
                ├── Then the queued order recipient should match input
                ├── Then the queued order client should match the sender
                └── Then the queued order timestamp should be greater than 0.
    */
    function testQueueOperations_GivenValidRecipientAndAmount(
        address recipient_,
        uint96 amount_
    ) public {
        // Ensure valid inputs
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(recipient_ != address(paymentClient));
        vm.assume(recipient_ != address(_token));
        vm.assume(recipient_ != address(_orchestrator.fundingManager()));
        vm.assume(recipient_ != address(_orchestrator.fundingManager().token()));
        vm.assume(amount_ > 0 && amount_ < type(uint96).max);

        // Setup
        _authorizer.setIsAuthorized(address(queue), true);

        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        // First add the order to the payment client
        paymentClient.addPaymentOrderUnchecked(order);

        // Setup tokens using our new helper
        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);

        vm.prank(address(paymentClient));
        uint orderId =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        assertTrue(orderId > 0, "Order ID should be greater than 0");
        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            1,
            "Queue size should be 1"
        );

        // Verify order details
        helper_assertOrderMatch(
            orderId,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    // ================================================================================
    // Test Valid Payment Receiver

    /* Test testValidPaymentReceiver_GivenValidAddress()
    └── Given a valid recipient address
        └── When validating the payment receiver
            └── Then it should return true.
    */
    function testValidPaymentReceiver_GivenValidAddress() public {
        assertTrue(queue.exposed_validPaymentReceiver(makeAddr("valid")));
    }

    /* Test testValidPaymentReceiver_RevertGivenInvalidAddress()
        └── Given an invalid recipient address
            └── When validating the payment receiver
                └── Then it should return false.
    */
    function testValidPaymentReceiver_RevertGivenInvalidAddress() public {
        assertFalse(queue.exposed_validPaymentReceiver(address(0)));
        assertFalse(queue.exposed_validPaymentReceiver(address(queue)));
    }

    // ================================================================================
    // Test Valid Total Amount

    /* Test testValidTotalAmount_GivenValidAmount()
        └── Given a valid amount greater than 0
            └── When validating the total amount
                └── Then it should return true.
    */
    function testValidTotalAmount_GivenValidAmount() public {
        assertTrue(queue.exposed_validTotalAmount(100));
    }

    /* Test testValidTotalAmount_RevertGivenZeroAmount()
        └── Given an amount equal to 0
            └── When validating the total amount
                └── Then it should return false.
    */
    function testValidTotalAmount_RevertGivenZeroAmount() public {
        assertFalse(queue.exposed_validTotalAmount(0));
    }

    // ================================================================================
    // Test Valid Token Balance

    /* Test testValidTokenBalance_GivenSufficientBalance()
        └── Given a user with sufficient token balance
            └── When validating the token balance
                └── Then it should return true.
    */
    function testValidTokenBalance_GivenSufficientBalance() public {
        address user_ = makeAddr("user");
        deal(address(_token), user_, 1000);

        vm.startPrank(user_);
        _token.approve(address(queue), 500); // Dar allowance al contrato queue
        assertTrue(queue.exposed_validTokenBalance(address(_token), user_, 500));
        vm.stopPrank();
    }

    /* Test testValidTokenBalance_RevertGivenInsufficientBalance()
        └── Given a user with insufficient token balance
            └── When validating the token balance
                └── Then it should return false.
    */
    function testValidTokenBalance_RevertGivenInsufficientBalance(
        uint96 amount_
    ) public {
        vm.assume(amount_ > 0);

        address user_ = makeAddr("user");
        deal(address(_token), user_, amount_ - 1);

        vm.startPrank(user_);
        assertFalse(
            queue.exposed_validTokenBalance(address(_token), user_, amount_)
        );
        vm.stopPrank();
    }

    /* Test testValidTokenBalance_GivenSufficientAllowance()
        └── Given a user with sufficient token balance and allowance
            └── When validating the token balance with half the approved amount
                └── Then it should return true.
    */
    function testValidTokenBalance_GivenSufficientAllowance(
        uint amount_,
        address user_
    ) public {
        vm.assume(user_ != address(0));
        vm.assume(user_ != address(queue));
        vm.assume(user_ != address(this));

        amount_ = bound(amount_, 1, 1e30);

        deal(address(_token), user_, amount_);
        vm.startPrank(user_);
        _token.approve(address(queue), amount_);
        vm.stopPrank();

        assertTrue(
            queue.exposed_validTokenBalance(address(_token), user_, amount_ / 2)
        );
    }

    /* Test testValidTokenBalance_RevertGivenInsufficientAllowance()
        └── Given a user with insufficient allowance
            └── When validating the token balance with double the approved amount
                └── Then it should return false.
    */
    function testValidTokenBalance_RevertGivenInsufficientAllowance(
        uint amount_,
        address user_
    ) public {
        vm.assume(user_ != address(0));
        vm.assume(user_ != address(queue));
        vm.assume(user_ != address(this));

        amount_ = bound(amount_, 1, 1e30);

        deal(address(_token), user_, amount_);
        vm.startPrank(user_);
        _token.approve(address(queue), amount_);
        vm.stopPrank();

        assertFalse(
            queue.exposed_validTokenBalance(address(_token), user_, amount_ * 2)
        );
    }

    /* Test testValidTotalAmount_GivenAmount()
        └── Given any amount
            └── When validating the total amount
                └── Then it should return true for non-zero amounts and false for zero.
    */
    function testValidTotalAmount_GivenAmount(uint amount_) public {
        if (amount_ == 0) {
            assertFalse(
                queue.exposed_validTotalAmount(amount_),
                "Zero amount should be invalid."
            );
        } else {
            assertTrue(
                queue.exposed_validTotalAmount(amount_),
                "Non-zero amount should be valid."
            );
        }
    }

    /* Test testValidPaymentReceiver_GivenValidAddress()
        └── Given a valid recipient address that is not:
            ├── address(0)
            ├── queue address
            ├── orchestrator address
            └── token address
                └── When validating the payment receiver
                    └── Then it should return true.
    */
    function testValidPaymentReceiver_GivenValidAddress(address receiver_)
        public
    {
        vm.assume(receiver_ != address(0));
        vm.assume(receiver_ != address(queue));
        vm.assume(receiver_ != address(_orchestrator));
        vm.assume(receiver_ != address(msg.sender));
        vm.assume(receiver_ != address(this));
        vm.assume(receiver_ != address(_orchestrator.fundingManager()));
        vm.assume(receiver_ != address(_orchestrator.fundingManager().token()));

        assertTrue(
            queue.exposed_validPaymentReceiver(receiver_),
            "Valid receiver marked as invalid."
        );
    }

    /* Test testValidTokenBalance_GivenBalanceAndAmount()
        └── Given a user with a token balance and approval
            └── When validating the token balance
                ├── If balance is greater than or equal to amount
                │   └── Then it should return true.
                └── If balance is less than amount
                    └── Then it should return false.
    */
    function testValidTokenBalance_GivenBalanceAndAmount(
        uint balance_,
        uint amount_
    ) public {
        vm.assume(amount_ > 0);

        address user_ = makeAddr("user");
        deal(address(_token), user_, balance_);

        vm.startPrank(user_);
        _token.approve(address(queue), amount_);
        vm.stopPrank();

        bool isValid_ =
            queue.exposed_validTokenBalance(address(_token), user_, amount_);

        if (balance_ >= amount_) {
            assertTrue(isValid_, "Sufficient balance marked as invalid.");
        } else {
            assertFalse(isValid_, "Insufficient balance marked as valid.");
        }
    }

    /* Test testGetPaymentQueueId_GivenFlagsAndData()
        └── Given flags and data for queue ID retrieval
            └── When validating the payment queue ID
                ├── If ORDER_ID bit is set and data exists
                │   └── Then it should return the correct queue ID.
                └── If ORDER_ID bit is not set or data is empty
                    └── Then it should return 0.
    */
    function testGetPaymentQueueId_GivenFlagsAndData(
        uint queueId_,
        uint8 flagBits_,
        uint8 dataLength_
    ) public {
        dataLength_ = uint8(bound(dataLength_, 0, 10));
        bytes32 flags_ = bytes32(uint(flagBits_));

        bytes32[] memory data_ = new bytes32[](dataLength_);
        if (dataLength_ > 0) {
            data_[0] = bytes32(queueId_);
        }

        uint retrievedId_ = queue.exposed_getPaymentQueueId(flags_, data_);

        if ((flagBits_ & 1 == 1) && dataLength_ > 0) {
            assertEq(
                retrievedId_,
                queueId_,
                "Queue ID mismatch when flag is set and data exists."
            );
        } else {
            assertEq(
                retrievedId_,
                0,
                "Should return 0 when flag is not set or data is empty."
            );
        }
    }

    // ================================================================================
    // Test Set Max Orders Per Execution

    /* Test: Function setMaxOrdersPerExecution()
        └── Given: Caller is not permissioned
            └── When: the function setMaxOrdersPerExecution() is called
                └── Then: it should revert (modifier in place test)
    */

    function testSetMaxOrdersPerExecution_ModifierInPlace() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        queue.setMaxOrdersPerExecution(100);
    }

    /* Test: Function setMaxOrdersPerExecution()
        ├── Given the caller has the QUEUE_OPERATOR_ROLE_ADMIN role
        └── And the number of orders per execution is zero
            └── When the function setMaxOrdersPerExecution is called
                └── Then it should revert with Module__PP_Queue_ZeroAmount
    */
    function testSetMaxOrdersPerExecution_revertGivenZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPP_Queue_v1.Module__PP_Queue_ZeroAmount.selector
            )
        );
        queue.setMaxOrdersPerExecution(0);
    }

    /* Test: Function setMaxOrdersPerExecution()
        ├── Given the caller has the QUEUE_OPERATOR_ROLE_ADMIN role
        └── And the number of orders per execution is not zero
            └── When the function setMaxOrdersPerExecution is called
                └── Then it should update the state
    */
    function testSetMaxOrdersPerExecution_worksGivenQueueOperatorAndNonZeroAmount(
        uint maxOrdersPerExecution_
    ) public {
        // Setup
        uint currentMaxOrdersPerExecution_ = queue.getMaxOrdersPerExecution();
        vm.assume(maxOrdersPerExecution_ > 0);
        vm.assume(maxOrdersPerExecution_ != DEFAULT_MAX_ORDERS_PER_EXECUTION);

        // Test
        queue.setMaxOrdersPerExecution(maxOrdersPerExecution_);

        // Post Assertion
        assertNotEq(
            queue.getMaxOrdersPerExecution(), currentMaxOrdersPerExecution_
        );
        assertEq(queue.getMaxOrdersPerExecution(), maxOrdersPerExecution_);
    }

    // ================================================================================
    // Test Get Queue Size For Client

    /* Test testGetQueueSizeForClient_GivenEmptyAndFilledQueue()
        └── Given a client's queue
            └── When checking the queue size
                ├── Then it should be 0 initially.
                ├── Then it should be 1 after adding an order.
                └── Then it should be 0 after canceling the order.
    */
    function testGetQueueSizeForClient_GivenEmptyAndFilledQueue() public {
        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            0,
            "Initial queue size should be 0."
        );

        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: makeAddr("recipient"),
            amount: 100,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(paymentClient), 100);
        paymentClient.exposed_addToOutstandingTokenAmounts(address(_token), 100);
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), 100);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
        vm.stopPrank();

        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            1,
            "Queue size should be 1 after adding."
        );

        queue.cancelPaymentOrderThroughQueueId(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            0,
            "Queue size should be 0 after canceling."
        );
    }

    /* Test testGetQueueSizeForClient_GivenMultipleOrders()
        └── Given a valid client with multiple orders
            └── When managing the queue
                ├── Then it should be 0 initially.
                ├── Then it should match numOrders after adding orders.
                ├── Then it should decrease after each cancellation.
                └── Then it should be 0 for non-existent client.
    */

    function testGetQueueSizeForClient_GivenMultipleOrders(uint8 numOrders_)
        public
    {
        numOrders_ = uint8(bound(uint(numOrders_), 1, 10));

        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            0,
            "Initial queue size should be 0."
        );

        uint[] memory orderIds_ = new uint[](numOrders_);

        for (uint8 i = 0; i < numOrders_; i++) {
            (bytes32 flags_, bytes32[] memory data_) =
                helper__encodePaymentOrderData(i + 1);
            IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
            IERC20PaymentClientBase_v2.PaymentOrder({
                recipient: makeAddr(string.concat("recipient", vm.toString(i))),
                amount: 100,
                paymentToken: address(_token),
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: flags_,
                data: data_
            });

            _token.mint(address(paymentClient), 100);
            paymentClient.exposed_addToOutstandingTokenAmounts(
                address(_token), 100
            );
            vm.startPrank(address(paymentClient));
            _token.approve(address(queue), 100);
            orderIds_[i] = queue.exposed_addPaymentOrderToQueue(
                order_, address(paymentClient)
            );
            vm.stopPrank();
        }

        assertEq(
            queue.getQueueSizeForClient(address(paymentClient)),
            numOrders_,
            "Queue size should match number of orders added."
        );

        for (uint8 i = 0; i < numOrders_; i++) {
            // Approve tokens for cancellation
            vm.startPrank(address(paymentClient));
            _token.approve(address(queue), 100);
            vm.stopPrank();

            queue.cancelPaymentOrderThroughQueueId(
                orderIds_[i], IERC20PaymentClientBase_v2(address(paymentClient))
            );

            assertEq(
                queue.getQueueSizeForClient(address(paymentClient)),
                numOrders_ - (i + 1),
                "Queue size should decrease after each cancellation."
            );
        }

        assertEq(
            queue.getQueueSizeForClient(address(0)),
            0,
            "Queue size should be 0 for non-existent client."
        );
    }

    /* Test testGetOrder_GivenValidOrderId()
        └── Given a valid order ID
            └── When retrieving the order
                ├── Then it should return the correct order details.
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                └── Then state should be QUEUED.
    */
    function testGetOrder_GivenValidOrderId() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order, address(this));

        helper_assertOrderMatch(
            orderId_,
            address(this),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    /* Test testGetOrder_GivenValidOrderFuzz()
        └── Given a valid order with fuzzed inputs
            └── When retrieving the order
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                ├── Then origin chain ID should match.
                ├── Then target chain ID should match.
                ├── Then state should be PENDING.
                ├── Then order ID should match.
                └── Then client should match.
    */
    function testGetOrder_GivenValidOrder(address recipient_, uint96 amount_)
        public
    {
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(queue));
        vm.assume(recipient_ != address(msg.sender));
        vm.assume(recipient_ != address(this));
        vm.assume(recipient_ != address(_orchestrator));
        vm.assume(recipient_ != address(_orchestrator.fundingManager()));
        vm.assume(recipient_ != address(_orchestrator.fundingManager().token()));
        vm.assume(address(paymentClient) != recipient_);
        amount_ = uint96(bound(uint(amount_), 1, 1e30));

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);

        vm.prank(address(paymentClient));
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        helper_assertOrderMatch(
            orderId_,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    /* Test testGetOrder_RevertGivenInvalidOrderId()
        └── Given an invalid order ID
            └── When retrieving the order
                └── Then it should revert with Module__PP_Queue_InvalidOrderId.
    */
    function testGetOrder_RevertGivenInvalidOrderId() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                1
            )
        );
        queue.getOrder(1, IERC20PaymentClientBase_v2(address(this)));
    }

    /* Test testGetOrder_GivenCancelledOrder()
        └── Given a cancelled order
            └── When retrieving the order
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                └── Then state should be CANCELLED.
    */

    function testGetOrder_GivenCancelledOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
        vm.stopPrank();

        // Approve again for cancellation
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);

        queue.cancelPaymentOrderThroughQueueId(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        helper_assertOrderMatch(
            orderId_,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.CANCELLED
        );
    }

    /* Test testGetOrder_GivenProcessedOrder()
        └── Given a processed order
            └── When retrieving the order
                ├── Then recipient should match.
                ├── Then amount should match.
                ├── Then token should match.
                └── Then state should be PROCESSED.
    */
    function testGetOrder_GivenProcessedOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(paymentClient), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));

        queue.exposed_updateOrderState(
            orderId_,
            address(paymentClient),
            IPP_Queue_v1.RedemptionState.PROCESSED
        );
        queue.exposed_removeFromQueue(orderId_, address(paymentClient));

        helper_assertOrderMatch(
            orderId_,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PROCESSED
        );
    }

    /* Test testGetOrderQueue_GivenEmptyQueue()
        └── Given an empty queue
            └── When retrieving the queue
                └── Then it should return an empty array.
    */
    function testGetOrderQueue_GivenEmptyQueue() public {
        uint[] memory orders_ = queue.getOrderQueue(address(this));
        assertEq(orders_.length, 0, "Queue should be empty.");
    }

    /* Test testGetOrderQueue_GivenSingleOrder()
        └── Given a queue with a single order
            └── When retrieving the queue
                └── Then it should return array with one order ID.
    */
    function testGetOrderQueue_GivenSingleOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order, address(this));

        uint[] memory orders_ = queue.getOrderQueue(address(this));
        assertEq(orders_.length, 1, "Queue should have one order.");
        assertEq(orders_[0], orderId_, "Order ID should match.");
    }

    /* Test testGetOrderQueue_GivenMultipleOrders()
        └── Given a queue with multiple orders
            └── When retrieving the queue
                ├── Then array length should match order count.
                └── Then all order IDs should match.
    */
    function testGetOrderQueue_GivenMultipleOrders(uint8 orderCount_) public {
        orderCount_ = uint8(bound(orderCount_, 2, 5));
        uint[] memory orderIds_ = new uint[](orderCount_);

        for (uint i_; i_ < orderCount_; i_++) {
            address recipient_ =
                makeAddr(string.concat("recipient", vm.toString(i_)));
            uint96 amount_ = 100;

            IERC20PaymentClientBase_v2.PaymentOrder memory order =
            helper_createTestPaymentOrder(
                recipient_, amount_, i_ + 1, address(_token)
            );

            helper_setupPaymentTokenBalanceAndApproval(amount_, _token);

            vm.prank(address(paymentClient));
            orderIds_[i_] = queue.exposed_addPaymentOrderToQueue(
                order, address(paymentClient)
            );
        }

        uint[] memory queueOrders_ = queue.getOrderQueue(address(paymentClient));
        assertEq(
            queueOrders_.length,
            orderCount_,
            "Queue length should match order count."
        );

        for (uint i_; i_ < orderCount_; i_++) {
            assertEq(queueOrders_[i_], orderIds_[i_], "Order ID should match.");
        }
    }

    /* Test testGetOrderQueue_GivenNonExistentClient()
        └── Given a non-existent client
            └── When retrieving the queue
                └── Then it should return an empty array.
    */
    function testGetOrderQueue_GivenNonExistentClient() public {
        address nonExistentClient_ = makeAddr("nonExistentClient");
        uint[] memory orders_ = queue.getOrderQueue(nonExistentClient_);
        assertEq(orders_.length, 0, "Queue should be empty.");
    }

    /* Test testAddPaymentOrderToQueue_RevertGivenInvalidOrder()
        └── Given an order with invalid recipient
            └── When adding order to queue
                └── Then it should revert with Module__PP_Queue_QueueOperationFailed.
    */
    function testAddPaymentOrderToQueue_RevertGivenInvalidOrder() public {
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: address(0),
            amount: 100,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_QueueOperationFailed(address)", address(this)
            )
        );
        queue.exposed_addPaymentOrderToQueue(order_, address(this));
    }

    // ================================================================================
    // Test Queue Operations

    /* Test testQueueOperations_GivenValidInputs()
        └── Given valid orders
            └── When performing queue operations
                ├── Then orders should be added correctly.
                ├── Then orders should be cancelled correctly.
                └── Then queue should be empty after operations.
    */
    function testQueueOperations_GivenValidInputs() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
        vm.stopPrank();

        uint[] memory queueBefore_ = queue.getOrderQueue(address(paymentClient));
        assertEq(queueBefore_.length, 1, "Queue should have one order.");
        assertEq(queueBefore_[0], orderId_, "Order ID should match.");

        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.cancelPaymentOrderThroughQueueId(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        uint[] memory queueAfter_ = queue.getOrderQueue(address(paymentClient));
        assertEq(queueAfter_.length, 0, "Queue should be empty after cancel.");
    }

    // ================================================================================
    // Test Get Queue Head

    /* Test testGetQueueHead_RevertGivenUninitializedQueue()
        └── Given an uninitialized queue
            └── When getting queue head
                └── Then it should revert with Module__PP_Queue_QueueOperationFailed.
    */
    function testGetQueueHead_RevertGivenUninitializedQueue() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_QueueOperationFailed(address)", address(this)
            )
        );
        queue.getQueueHead(address(this));
    }

    /* Test testGetQueueHead_GivenSingleOrder()
        └── Given a queue with one order
            └── When getting queue head
                └── Then it should return first order ID.
    */
    function testGetQueueHead_GivenSingleOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueHead(address(this)),
            orderId_,
            "Head should be first order ID."
        );
    }

    /* Test testGetQueueHead_GivenMultipleOrders()
        └── Given a queue with multiple orders
            └── When getting queue head
                └── Then it should return first order ID.
    */
    function testGetQueueHead_GivenMultipleOrders() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        // First order
        (bytes32 flags1_, bytes32[] memory data1_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order1_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags1_,
            data: data1_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order1_, address(paymentClient)
        );
        vm.stopPrank();

        assertEq(
            queue.getQueueHead(address(paymentClient)),
            firstOrderId_,
            "Head should be first order ID."
        );
        helper_assertOrderMatch(
            firstOrderId_,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PENDING
        );

        // Second order with different flags/data
        (bytes32 flags2_, bytes32[] memory data2_) =
            helper__encodePaymentOrderData(2);
        IERC20PaymentClientBase_v2.PaymentOrder memory order2_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags2_,
            data: data2_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order2_, address(paymentClient));
        vm.stopPrank();

        assertEq(
            queue.getQueueHead(address(paymentClient)),
            firstOrderId_,
            "Head should be first order ID."
        );
    }

    /* Test testGetQueueHead_GivenPartiallyProcessedQueue()
        └── Given a queue with multiple orders and first cancelled
            └── When getting queue head
                └── Then it should return second order ID.
    */
    function testGetQueueHead_GivenPartiallyProcessedQueue() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        // First order
        (bytes32 flags1_, bytes32[] memory data1_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order1_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags1_,
            data: data1_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order1_, address(paymentClient)
        );
        vm.stopPrank();

        // Second order with different flags/data
        (bytes32 flags2_, bytes32[] memory data2_) =
            helper__encodePaymentOrderData(2);
        IERC20PaymentClientBase_v2.PaymentOrder memory order2_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags2_,
            data: data2_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint secondOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order2_, address(paymentClient)
        );
        vm.stopPrank();

        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        assertEq(
            queue.getQueueHead(address(paymentClient)),
            secondOrderId_,
            "Head should be second order ID."
        );

        helper_assertOrderMatch(
            secondOrderId_,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    /* Test testGetQueueHead_GivenFullyProcessedQueue()
        └── Given a queue with all orders cancelled
            └── When getting queue head
                └── Then it should return sentinel value.
    */
    function testGetQueueHead_GivenFullyProcessedQueue() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        // First order
        (bytes32 flags1_, bytes32[] memory data1_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order1_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags1_,
            data: data1_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order1_, address(paymentClient)
        );
        vm.stopPrank();

        // Second order with different flags/data
        (bytes32 flags2_, bytes32[] memory data2_) =
            helper__encodePaymentOrderData(2);
        IERC20PaymentClientBase_v2.PaymentOrder memory order2_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags2_,
            data: data2_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint secondOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order2_, address(paymentClient)
        );
        vm.stopPrank();

        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.cancelPaymentOrderThroughQueueId(
            secondOrderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        assertEq(
            queue.getQueueHead(address(paymentClient)),
            type(uint).max,
            "Head should be sentinel value."
        );
    }

    /* Test testGetQueueTail_GivenUninitializedQueue()
        └── Given an uninitialized queue
            └── When getting queue tail
                └── Then it should return 0 as default value.
    */
    function testGetQueueTail_GivenUninitializedQueue() public {
        assertEq(
            queue.getQueueTail(address(this)),
            0,
            "Tail should be 0 for uninitialized queue"
        );
    }

    /* Test testGetQueueTail_GivenSingleOrder()
        └── Given a queue with one order
            └── When getting queue tail
                └── Then it should return first order ID.
    */
    function testGetQueueTail_GivenSingleOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertEq(
            queue.getQueueTail(address(this)),
            orderId_,
            "Tail should be first order ID."
        );
    }

    /* Test testGetQueueTail_GivenMultipleOrders()
        └── Given a queue with multiple orders
            └── When getting queue tail
                └── Then it should return last order ID.
    */
    function testGetQueueTail_GivenMultipleOrders() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        // First order
        (bytes32 flags1_, bytes32[] memory data1_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order1_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags1_,
            data: data1_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.exposed_addPaymentOrderToQueue(order1_, address(paymentClient));
        vm.stopPrank();

        // Second order with different flags/data
        (bytes32 flags2_, bytes32[] memory data2_) =
            helper__encodePaymentOrderData(2);
        IERC20PaymentClientBase_v2.PaymentOrder memory order2_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags2_,
            data: data2_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint lastOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order2_, address(paymentClient)
        );
        vm.stopPrank();

        assertEq(
            queue.getQueueTail(address(paymentClient)),
            lastOrderId_,
            "Tail should be last order ID."
        );
        helper_assertOrderMatch(
            lastOrderId_,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    /* Test testGetQueueTail_GivenPartiallyProcessedQueue()
        └── Given a queue with multiple orders and first cancelled
            └── When getting queue tail
                └── Then it should return last order ID.
    */
    function testGetQueueTail_GivenPartiallyProcessedQueue() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        // First order
        (bytes32 flags1_, bytes32[] memory data1_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order1_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags1_,
            data: data1_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order1_, address(paymentClient)
        );
        vm.stopPrank();

        // Second order with different flags/data
        (bytes32 flags2_, bytes32[] memory data2_) =
            helper__encodePaymentOrderData(2);
        IERC20PaymentClientBase_v2.PaymentOrder memory order2_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags2_,
            data: data2_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint lastOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order2_, address(paymentClient)
        );
        vm.stopPrank();

        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        assertEq(
            queue.getQueueTail(address(paymentClient)),
            lastOrderId_,
            "Tail should be last order ID."
        );

        helper_assertOrderMatch(
            lastOrderId_,
            address(paymentClient),
            recipient_,
            amount_,
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    /* Test testGetQueueTail_GivenFullyProcessedQueue()
        └── Given a queue with all orders cancelled
            └── When getting queue tail
                └── Then it should return sentinel value.
    */
    function testGetQueueTail_GivenFullyProcessedQueue() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        // First order
        (bytes32 flags1_, bytes32[] memory data1_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order1_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags1_,
            data: data1_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint firstOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order1_, address(paymentClient)
        );
        vm.stopPrank();

        // Second order with different flags/data
        (bytes32 flags2_, bytes32[] memory data2_) =
            helper__encodePaymentOrderData(2);
        IERC20PaymentClientBase_v2.PaymentOrder memory order2_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags2_,
            data: data2_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint secondOrderId_ = queue.exposed_addPaymentOrderToQueue(
            order2_, address(paymentClient)
        );
        vm.stopPrank();

        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.cancelPaymentOrderThroughQueueId(
            firstOrderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        queue.cancelPaymentOrderThroughQueueId(
            secondOrderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        assertEq(
            queue.getQueueTail(address(paymentClient)),
            type(uint).max,
            "Tail should be sentinel value."
        );
    }

    // ================================================================================
    // Test Process Next Order

    /* Test function _processNextOrder()
        └── Given a valid order in queue
            └── When processing next order
                ├── Then it should succeed.
                └── Then order should be processed.
    */
    function testInternalProcessNextOrder_worksGivenValidOrderReturnsTrue(
        address recipient_,
        uint96 amount_
    ) public {
        // Validate inputs
        recipient_ = helper_validPaymentReceiver(recipient_);
        amount_ = uint96(bound(amount_, 1, type(uint96).max));

        // Setup
        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));
        // Setup tokens using helper
        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);
        // Add order to queue
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        // Get value for pre-assertions
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // Pre-assertions
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PENDING)
        );
        assertEq(
            _token.balanceOf(recipient_), 0, "Recipient should have no balance"
        );
        assertEq(
            _token.balanceOf(address(paymentClient)),
            amount_,
            "Payment client should have the correct balance"
        );

        // Test Function Call
        vm.prank(address(paymentClient));
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));
        assertTrue(success_, "Order processing should succeed.");

        // Get value for post-assertions
        queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
        // Post-assertions
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSED)
        );
        assertEq(_token.balanceOf(recipient_), amount_);
        assertEq(
            _token.balanceOf(address(paymentClient)),
            0,
            "Payment client should have no balance"
        );
    }

    /* Test testProcessNextOrder_GivenEmptyQueue()
        └── Given an empty queue
            └── When processing next order
                └── Then it should return false.
    */
    function testProcessNextOrder_GivenEmptyQueue() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(paymentClient), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
        queue.exposed_removeFromQueue(orderId_, address(paymentClient));

        vm.prank(address(paymentClient));
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));
        assertFalse(success_, "Processing empty queue should fail.");
    }

    // ================================================================================
    // Test Execute Payment Transfer

    /* Test: Function _executePaymentTransfer()
        └── Given the payment transfer succeeds
            └── When the function _executePaymentTransfer() is called
                ├── Then the order state is set to PROCESSED
                └── And the order is removed from the queue
    */
    function testInternalExecutePaymentTransfer_worksGivenStateIsProcessedAndRemovedFromQueue(
        address recipient_,
        uint96 amount_
    ) public {
        // Setup
        recipient_ = helper_validPaymentReceiver(recipient_);
        vm.assume(amount_ > 0);
        uint queueId = 1;

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(
            recipient_, amount_, queueId, address(_token)
        );
        // Mint tokens to payment client and approve PP Queue
        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);

        // Get value for pre-assertions
        uint orderId_ =
            helper_addPaymentOrderToQueue(order, address(paymentClient));
        uint queueSize_ = queue.getQueueSizeForClient(address(paymentClient));
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // pre-assertions
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PENDING)
        );
        assertEq(_token.balanceOf(recipient_), 0);
        assertEq(queueSize_, 1);

        // Test
        queue.exposed_executePaymentTransfer(orderId_, queuedOrder_);

        // Get values for post-assertions
        queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
        queueSize_ = queue.getQueueSizeForClient(address(paymentClient));

        // post-assertions
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSED)
        );
        assertEq(_token.balanceOf(recipient_), amount_);
        assertEq(queueSize_, 0);
    }

    /* Test: Function _executePaymentTransfer()
        └── Given the payment transfer fails (receiver blacklisted)
            └── When the function _executePaymentTransfer() is called
                ├── Then the order state is set to FAILED
                └── And the order is removed from the queue
    */

    function testInternalExecutePaymentTransfer_worksGivenStateIsFailedAndRemovedFromQueue(
        address recipient_,
        uint96 amount_
    ) public {
        // Setup
        recipient_ = helper_validPaymentReceiver(recipient_);
        vm.assume(amount_ > 0);
        uint queueId = 1;

        // Use non-standard token to blacklist recipient so the transfer state
        // will be set to fail
        NonStandardTokenMock nonStandardToken = new NonStandardTokenMock();
        nonStandardToken.setFailTransferTo(recipient_);

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(
            recipient_, amount_, queueId, address(nonStandardToken)
        );
        // Mint tokens to payment client and approve PP Queue
        helper_setupPaymentTokenBalanceAndApproval(
            amount_, ERC20Mock(address(nonStandardToken))
        );

        // Get value for pre-assertions
        uint orderId_ =
            helper_addPaymentOrderToQueue(order, address(paymentClient));
        uint queueSize_ = queue.getQueueSizeForClient(address(paymentClient));
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // pre-assertions
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PENDING)
        );
        assertEq(nonStandardToken.balanceOf(recipient_), 0);
        assertEq(nonStandardToken.balanceOf(address(paymentClient)), amount_);
        assertEq(queueSize_, 1);

        // Test
        queue.exposed_executePaymentTransfer(orderId_, queuedOrder_);

        // Get values for post-assertions
        queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
        queueSize_ = queue.getQueueSizeForClient(address(paymentClient));

        // post-assertions
        assertEq(
            uint(queuedOrder_.state_), uint(IPP_Queue_v1.RedemptionState.FAILED)
        );
        assertEq(nonStandardToken.balanceOf(recipient_), 0);
        assertEq(nonStandardToken.balanceOf(address(queue)), amount_);
        assertEq(queueSize_, 0);
    }

    /* Test testExecutePaymentTransfer_GivenValidOrder()
        └── Given a valid payment order
            └── When executing transfer
                ├── Then it should succeed.
                ├── Then recipient should receive tokens.
                └── Then queue balance should decrease.
    */
    function testExecutePaymentTransfer_GivenValidOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        // Setup tokens using helper
        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);

        // Add order to queue
        queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        // Process the payment queue for the client
        vm.prank(address(paymentClient));
        queue.exposed_processNextOrder(address(paymentClient));

        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should receive tokens."
        );
        assertEq(
            _token.balanceOf(address(queue)), 0, "Queue balance should be zero."
        );
    }

    /* Test testExecutePaymentTransfer_RevertGivenInvalidOrder()
        └── Given an order with insufficient balance
            └── When executing transfer
                └── Then it should revert with Module__PP_Queue_TransferFailed.
    */
    function testExecutePaymentTransfer_RevertGivenInvalidOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(0);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_QueueOperationFailed(address)",
                address(paymentClient)
            )
        );
        queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
    }

    /* Test testExecutePaymentTransfer_RevertGivenInsufficientBalance()
        └── Given order with insufficient balance
            └── When processing next order
                └── Then it should:
                    └── Return false
                    └── Keep order in PENDING state
    */
    function testExecutePaymentTransfer_RevertGivenInsufficientBalance()
        public
    {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(paymentClient), amount_ - 1);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );

        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);

        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));

        vm.prank(address(paymentClient));
        bool success = queue.exposed_processNextOrder(address(paymentClient));
        assertFalse(
            success, "Processing should fail due to insufficient balance"
        );

        IPP_Queue_v1.QueuedOrder memory order =
            queue.getOrder(orderId_, paymentClient);
        assertEq(
            uint(order.state_),
            uint(IPP_Queue_v1.RedemptionState.PENDING),
            "Order should remain in PENDING state"
        );
    }

    /* Test testOrderExists_GivenValidOrder()
        └── Given a valid order in queue
            └── When checking if order exists
                └── Then it should return true.
    */
    function testOrderExists_GivenValidOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        assertTrue(
            queue.exposed_orderExists(
                orderId_, IERC20PaymentClientBase_v2(address(this))
            ),
            "Order should exist."
        );
    }

    /* Test testOrderExists_GivenInvalidOrder()
        └── Given a non-existent order ID
            └── When checking if order exists
                └── Then it should return false.
    */
    function testOrderExists_GivenInvalidOrder() public {
        assertFalse(
            queue.exposed_orderExists(
                999, IERC20PaymentClientBase_v2(address(this))
            ),
            "Invalid order should not exist."
        );
    }

    /* Test testOrderExists_GivenInvalidClient()
        └── Given a non-existent client
            └── When checking if order exists
                └── Then it should return false.
    */
    function testOrderExists_GivenInvalidClient() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        address invalidClient_ = makeAddr("invalidClient");
        assertFalse(
            queue.exposed_orderExists(
                orderId_, IERC20PaymentClientBase_v2(invalidClient_)
            ),
            "Order should not exist for invalid client."
        );
    }

    /* Test testValidQueueId_GivenValidId()
        └── Given a valid queue ID
            └── When checking if ID is valid
                └── Then it should return true.
    */
    function testValidQueueId_GivenValidId() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);

        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));

        assertTrue(
            queue.exposed_validQueueId(orderId_ + 1, address(paymentClient)),
            "Queue ID should be valid."
        );
    }

    // ================================================================================
    // Test Update Order State

    /* Test testUpdateOrderState_GivenValidOrder()
        └── Given a valid order in queue
            └── When updating order state
                ├── Then it should update state.
                └── Then state should match expected value.
    */
    function testUpdateOrderState_GivenValidOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        queue.exposed_updateOrderState(
            orderId_,
            address(paymentClient),
            IPP_Queue_v1.RedemptionState.PROCESSED
        );

        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PROCESSED),
            "State should be PROCESSED."
        );
    }

    // ================================================================================
    // Test Remove From Queue

    /* Test testRemoveFromQueue_GivenValidOrder()
        └── Given a valid order in queue
            └── When removing order
                ├── Then it should be removed.
                └── Then queue should be empty.
    */
    function testRemoveFromQueue_GivenValidOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order, address(paymentClient));

        queue.exposed_removeFromQueue(orderId_, address(paymentClient));

        uint[] memory orders_ = queue.getOrderQueue(address(paymentClient));
        assertEq(orders_.length, 0, "Queue should be empty.");
    }

    // ================================================================================
    // Test

    /* Test: internal _lowLevelTransfer()
        ├── Given the recipient is not valie
        │   └── When the function _lowLevelTransfer() is called
        │       └── Then it should return false
        └── Given the recipient is valid
            └── When the function _lowLevelTransfer() is called
                └── Then it should return true
    */
    function testInternalLowLevelTransfer_worksGivenInvalidRecipientReturnsFalse(
        uint amount_
    ) public {
        // Setup
        address invalidRecipient_ = makeAddr("invalidRecipient");
        vm.assume(amount_ > 0);
        // initiate token and set fail transfer to invalid recipient
        NonStandardTokenMock nonStandardToken = new NonStandardTokenMock();
        nonStandardToken.setFailTransferTo(invalidRecipient_);
        // mint tokens to payment client and approve queue to spend
        nonStandardToken.mint(address(paymentClient), amount_);
        vm.prank(address(paymentClient));
        nonStandardToken.approve(address(queue), amount_);

        // Assert pre-conditions
        assertEq(
            nonStandardToken.balanceOf(address(paymentClient)),
            amount_,
            "Payment Client should have tokens"
        );
        assertEq(
            nonStandardToken.balanceOf(invalidRecipient_),
            0,
            "Invalid recipient should have no tokens"
        );

        // Test
        bool success_ = queue.exposed_lowLevelTransfer(
            address(_token), address(paymentClient), invalidRecipient_, amount_
        );
        // Assert
        assertFalse(success_, "Transfer should fail");
        assertEq(
            nonStandardToken.balanceOf(address(paymentClient)),
            amount_,
            "Payment Client should have tokens"
        );
        assertEq(
            nonStandardToken.balanceOf(invalidRecipient_),
            0,
            "Invalid recipient should have no tokens"
        );
    }

    function testInternalLowLevelTransfer_worksGivenValidRecipientReturnsTrue(
        uint amount_
    ) public {
        // Setup
        address validRecipient_ = makeAddr("validRecipient");
        vm.assume(amount_ > 0);
        // mint tokens to payment client and approve queue to spend
        _token.mint(address(paymentClient), amount_);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);

        // Assert pre-conditions
        assertEq(
            _token.balanceOf(address(paymentClient)),
            amount_,
            "Payment Client should have tokens"
        );
        assertEq(
            _token.balanceOf(validRecipient_),
            0,
            "Recipient should have no tokens"
        );

        // Test
        bool success_ = queue.exposed_lowLevelTransfer(
            address(_token), address(paymentClient), validRecipient_, amount_
        );

        // Assert post-conditions
        assertTrue(success_, "Transfer should succeed");
        assertEq(
            _token.balanceOf(address(paymentClient)),
            0,
            "Payment Client should have no tokens"
        );
        assertEq(
            _token.balanceOf(validRecipient_),
            amount_,
            "Recipient should have tokens"
        );
    }

    /* Test: internal _tryPaymentTransfer()
        └── Given the payment processor has enough balance
            ├── And recipient is not valid (transfer fails)
            │   └── When the function _tryPaymentTransfer() is called
            │       ├── Then the low level transfer should fail
            │       ├── And the amount should be transferred to the payment processor
            │       ├── And the amount is added to the unclaimable amounts
            │       └── And the function should return false
            │       └── And the outstanding amount is updated
            └── And the recipient is valid (transfer succeeds)
                └── When the function _tryPaymentTransfer() is called
                    ├── Then the low level transfer should succeed
                    ├── And the amount should be transferred to the recipient
                    ├── And an event should be emitted
                    ├── And the fee is transferred to the protocol treasury
                    └── And the function should return true
                    └── And the outstanding amount is updated
    */
    function testInternalTryPaymentTransfer_worksGivenAmountTransferredToPPAndReturnFalse(
        uint amount_
    ) public {
        // Setup
        address invalidRecipient_ = makeAddr("invalidRecipient");
        vm.assume(amount_ > 0);
        // initiate token and set fail transfer to invalid recipient
        NonStandardTokenMock nonStandardToken = new NonStandardTokenMock();
        nonStandardToken.setFailTransferTo(invalidRecipient_);
        // mint tokens to payment client and approve queue to spend
        nonStandardToken.mint(address(paymentClient), amount_);
        vm.prank(address(paymentClient));
        nonStandardToken.approve(address(queue), amount_);
        // add tokens to outstanding amounts in payment client mock
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(nonStandardToken), amount_
        );

        // Assert pre-conditions
        assertEq(
            nonStandardToken.balanceOf(address(paymentClient)),
            amount_,
            "Payment Client should have tokens"
        );
        assertEq(
            nonStandardToken.balanceOf(address(queue)),
            0,
            "Payment Processor should have no tokens"
        );
        assertEq(
            paymentClient.outstandingTokenAmount(address(nonStandardToken)),
            amount_,
            "Payment Client should have tokens in outstanding amounts"
        );

        // Test
        bool success_ = queue.exposed_tryPaymentTransfer(
            address(nonStandardToken),
            address(paymentClient),
            invalidRecipient_,
            amount_,
            false // don't collect protocol fee when cancelling
        );

        // Assert post-conditions
        assertFalse(
            success_,
            "Should return false as transfer to invalid recipient failed"
        );

        assertEq(
            nonStandardToken.balanceOf(address(paymentClient)),
            0,
            "Payment Client should have no tokens"
        );
        assertEq(
            nonStandardToken.balanceOf(address(queue)),
            amount_,
            "Payment Processor should have tokens"
        );
        assertEq(
            paymentClient.outstandingTokenAmount(address(nonStandardToken)),
            0,
            "Payment Client should have no tokens in outstanding amounts"
        );
    }

    function testInternalTryPaymentTransfer_worksGivenAmountTransferredToRecipientAndReturnTrue(
        uint amount_,
        uint protocolFee_,
        bool collectProtocolFee_
    ) public {
        // Setup
        address validRecipient_ = makeAddr("validRecipient");
        amount_ = bound(amount_, 1e18, type(uint64).max);
        // Set protocol fee
        protocolFee_ = bound(protocolFee_, 10, feeManager.maxFee());
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(queue),
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            true,
            protocolFee_
        );
        // mint tokens to payment client and approve queue to spend
        _token.mint(address(paymentClient), amount_);
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        // add tokens to outstanding amounts in payment client mock
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        // Get protocol treasury
        address protocolTreasury_ = feeManager.getDefaultProtocolTreasury();
        uint netAmount;
        uint protocolFeeAmount;
        // Calculate protocol fee amount and net amount
        // based on if protocol fee is collected
        if (collectProtocolFee_) {
            protocolFeeAmount = amount_ * protocolFee_ / BPS;
            netAmount = amount_ - protocolFeeAmount;
        } else {
            netAmount = amount_;
            protocolFeeAmount = 0;
        }

        // Assert pre-conditions
        assertEq(
            _token.balanceOf(address(paymentClient)),
            amount_,
            "Payment Client should have tokens"
        );
        assertEq(
            _token.balanceOf(validRecipient_),
            0,
            "Recipient should have no tokens"
        );
        assertEq(
            paymentClient.outstandingTokenAmount(address(_token)),
            amount_,
            "Payment Client should have tokens in outstanding amounts"
        );
        assertEq(
            _token.balanceOf(protocolTreasury_),
            0,
            "Protocol treasury should have no tokens"
        );

        vm.expectEmit(true, true, true, true, address(queue));
        emit IPaymentProcessor_v2.TokensReleased(
            validRecipient_, address(_token), netAmount
        );
        emit IPaymentProcessor_v2.TokensReleased(
            protocolTreasury_, address(_token), protocolFeeAmount
        );
        emit IModule_v1.ProtocolFeeTransferred(
            address(_token), protocolTreasury_, protocolFeeAmount
        );
        // Test
        bool success_ = queue.exposed_tryPaymentTransfer(
            address(_token),
            address(paymentClient),
            validRecipient_,
            amount_,
            collectProtocolFee_
        );

        // Assert post-conditions
        assertTrue(success_, "Transfer should succeed");
        assertEq(
            _token.balanceOf(address(paymentClient)),
            0,
            "Payment Client should have no tokens"
        );
        assertEq(
            _token.balanceOf(validRecipient_),
            netAmount,
            "Recipient should have tokens"
        );
        assertEq(
            _token.balanceOf(protocolTreasury_),
            protocolFeeAmount,
            "Protocol treasury should have tokens"
        );
        assertEq(
            paymentClient.outstandingTokenAmount(address(_token)),
            0,
            "Payment Client should have no tokens in outstanding amounts"
        );
    }

    // ================================================================================
    // Test Claim Previously Unclaimable

    /* Test testClaimPreviouslyUnclaimable_GivenValidConditions()
        └── Given a previously unclaimable order
            └── When claiming order
                ├── Then it should succeed.
                └── Then recipient should receive tokens.
    */
    function testClaimPreviouslyUnclaimable_GivenValidConditions() public {
        paymentClient.exposed_addToOutstandingTokenAmounts(address(_token), 200);

        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        _token.mint(address(paymentClient), amount_ * 2);

        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_ * 2);
        queue.exposed_addUnclaimableOrder(order, address(paymentClient));
        _token.transfer(address(queue), amount_);
        vm.stopPrank();

        vm.prank(address(queue));
        _token.approve(address(queue), amount_);

        vm.prank(recipient_);
        queue.claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), recipient_
        );

        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should receive tokens."
        );
    }

    /* Test testClaimPreviouslyUnclaimable_GivenMultipleAmounts()
        └── Given multiple unclaimable orders
            └── When claiming orders
                ├── Then all claims should succeed.
                └── Then recipients should receive correct amounts.
    */
    function testClaimPreviouslyUnclaimable_GivenMultipleAmounts() public {
        address[] memory recipients_ = new address[](3);
        uint96[] memory amounts_ = new uint96[](3);
        uint totalAmount_;

        // First calculate total amount and mint it
        for (uint i_; i_ < 3; i_++) {
            recipients_[i_] =
                makeAddr(string.concat("recipient", vm.toString(i_)));
            amounts_[i_] = uint96((i_ + 1) * 100);
            totalAmount_ += amounts_[i_];
        }

        // Mint tokens to paymentClient
        _token.mint(address(paymentClient), totalAmount_);

        // Add orders to queue
        for (uint i_; i_ < 3; i_++) {
            (bytes32 flags_, bytes32[] memory data_) =
                helper__encodePaymentOrderData(i_ + 1);

            IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
            IERC20PaymentClientBase_v2.PaymentOrder({
                recipient: recipients_[i_],
                amount: amounts_[i_],
                paymentToken: address(_token),
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: flags_,
                data: data_
            });

            vm.startPrank(address(paymentClient));
            paymentClient.exposed_addToOutstandingTokenAmounts(
                address(_token), amounts_[i_]
            );
            _token.approve(address(queue), amounts_[i_]);
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
            vm.stopPrank();

            queue.exposed_addUnclaimableOrder(order_, address(paymentClient));

            // Transfer tokens to queue and approve queue to spend its own tokens
            vm.startPrank(address(paymentClient));
            _token.transfer(address(queue), amounts_[i_]);
            vm.stopPrank();

            vm.prank(address(queue));
            _token.approve(address(queue), amounts_[i_]);

            vm.prank(recipients_[i_]);
            queue.claimPreviouslyUnclaimable(
                address(paymentClient), address(_token), recipients_[i_]
            );

            assertEq(
                _token.balanceOf(recipients_[i_]),
                amounts_[i_],
                "Recipient should receive correct amount."
            );
        }
    }

    /* Test: Function executePaymentQueue()
        └── Given the number of orders in queue is greater than max orders per execution
            └── When the function executePaymentQueue() is called
                ├── Then the function should execute only until maxOrdersPerExecution is reached
                └── And the the remaining orders should be left in the queue
    */
    function testExecutePaymentQueue_worksGivenMaxOrdersPerExecutionIsReached()
        public
    {
        // Setup
        // Get max orders per execution
        uint maxOrdersPerExecution = queue.getMaxOrdersPerExecution();
        // Number of orders to add to the queue such that max orders per execution is reached
        uint numberOfOrders = maxOrdersPerExecution + 50;
        // Total amount of collateral that is being redeemed
        uint96 totalSellAmount = 1000e6;
        // Setup large queue with helper function
        helper_setupLargeQueue(totalSellAmount, numberOfOrders);
        // Get queue size before execution
        uint preExecutionQueueSize_ =
            queue.getQueueSizeForClient(address(paymentClient));

        // Pre-assertions
        assertEq(preExecutionQueueSize_, numberOfOrders);
        uint blockNumber_ = block.number;
        vm.roll(blockNumber_ + 10);
        // Test
        vm.prank(address(paymentClient));
        queue.exposed_executePaymentQueue(address(paymentClient));

        // Post-assertions
        uint postExecutionQueueSize_ =
            queue.getQueueSizeForClient(address(paymentClient));
        assertEq(
            postExecutionQueueSize_, numberOfOrders - maxOrdersPerExecution
        );
    }

    /* Test testExecutePaymentQueue_GivenMultipleOrders()
        └── Given multiple valid orders in queue
            └── When executing payment queue
                ├── Then all orders should be processed.
                └── Then recipients should receive correct amounts.
    */
    function testExecutePaymentQueue_GivenMultipleOrders() public {
        address[] memory recipients_ = new address[](3);
        uint96[] memory amounts_ = new uint96[](3);
        uint totalAmount_;

        vm.startPrank(address(paymentClient));

        // First calculate total amount and mint it
        for (uint i_; i_ < 3; i_++) {
            recipients_[i_] =
                makeAddr(string.concat("recipient", vm.toString(i_)));
            amounts_[i_] = uint96((i_ + 1) * 100);
            totalAmount_ += amounts_[i_];
        }

        // Mint total amount and approve it
        _token.mint(address(paymentClient), totalAmount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), totalAmount_
        );
        _token.approve(address(queue), totalAmount_);

        // Add orders to queue
        for (uint i_; i_ < 3; i_++) {
            (bytes32 flags_, bytes32[] memory data_) =
                helper__encodePaymentOrderData(i_ + 1);

            IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
            IERC20PaymentClientBase_v2.PaymentOrder({
                recipient: recipients_[i_],
                amount: amounts_[i_],
                paymentToken: address(_token),
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: flags_,
                data: data_
            });

            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
        }

        queue.exposed_executePaymentQueue(address(paymentClient));
        vm.stopPrank();

        for (uint i_; i_ < 3; i_++) {
            assertEq(
                _token.balanceOf(recipients_[i_]),
                amounts_[i_],
                "Recipient should receive correct amount."
            );
        }
    }

    // ================================================================================
    // Test Cancel Payment Order

    /* Test testCancelPaymentOrder_RevertGivenCompletedOrder()
        └── Given a completed order
            └── When attempting to cancel
                └── Then it should revert with Module__PP_Queue_InvalidStateTransition.
    */
    function testCancelPaymentOrder_RevertGivenCompletedOrder() public {
        // Setup: Create a payment order
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);

        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        // Mint tokens and set up allowances
        _token.mint(address(paymentClient), amount_);

        vm.startPrank(address(paymentClient));
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_
        );
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));

        // Execute queue to transition order to COMPLETED state
        queue.exposed_executePaymentQueue(address(paymentClient));
        vm.stopPrank();

        // Verify order is in PROCESSED state
        IPP_Queue_v1.QueuedOrder memory queuedOrder = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
        require(
            queuedOrder.state_ == IPP_Queue_v1.RedemptionState.PROCESSED,
            "Order should be in PROCESSED state"
        );

        // Attempt to transition from PROCESSED to CANCELLED should fail
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId_,
                uint8(IPP_Queue_v1.RedemptionState.PROCESSED),
                uint8(IPP_Queue_v1.RedemptionState.CANCELLED)
            )
        );

        // Try to update state directly - this should fail with InvalidStateTransition
        queue.exposed_updateOrderState(
            orderId_,
            address(paymentClient),
            IPP_Queue_v1.RedemptionState.CANCELLED
        );
    }

    /* Test testCancelPaymentOrder_RevertGivenCancelledOrder()
        └── Given a cancelled order
            └── When attempting to cancel again
                └── Then it should revert with Module__PP_Queue_InvalidState.
    */
    function testCancelPaymentOrder_RevertGivenCancelledOrder() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount_ * 2
        );
        vm.prank(address(paymentClient));
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));

        _token.approve(address(queue), amount_);
        queue.cancelPaymentOrderThroughQueueId(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_InvalidState()")
        );
        queue.cancelPaymentOrderThroughQueueId(orderId_, paymentClient);
    }

    /* Test: function _orderExisits()
        └── Given the order does not exist
            └── When the function _orderExists() is called
                └── Then it should return false.
    */
    function testInternalOrderExists_worksGivenNonExistentOrderReturnsFalse()
        public
    {
        // Setup
        uint nonExistentOrderId_ = 999;

        // Test function call
        bool orderExists_ =
            queue.exposed_orderExists(nonExistentOrderId_, paymentClient);

        // Post-assertions
        assertFalse(orderExists_, "Non-existent order should return false.");
    }

    /* Test: function _orderExisits()
        └── Given the order exists
            └── When the function _orderExists() is called
                └── Then it should return true.
    */
    function testInternalOrderExists_worksGivenExistentOrderReturnsTrue()
        public
    {
        // Setup
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));
        // Add payment order to queue, creating queue order
        uint orderId_ =
            helper_addPaymentOrderToQueue(order, address(paymentClient));

        // Test function call
        bool orderExists_ = queue.exposed_orderExists(orderId_, paymentClient);

        // Post-assertions
        assertTrue(orderExists_, "Order should exist.");
    }

    /*  Test: function _processNextOrder()
        └── Given queue is empty
            └── When the function _processNextOrder() is called
                └── Then it should return false

    */
    function testInternalProcessNextOrder_worksGivenEmptyQueueReturnsFalse()
        public
    {
        // Setup
        // Initiate queue for payment client
        queue.helper_initiateQueueForPaymentClient(address(paymentClient));

        // Test function call
        vm.prank(address(paymentClient));
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));

        // Post-assertions
        assertFalse(success_, "Queue should be empty.");
    }

    /* Test: function _processNextOrder()
        ├── Given queue is not empty
        └── And the order state is not PENDING
            └── When the function _processNextOrder() is called
                └── Then it should revert

    */
    function testInternalProcessNextOrder_revertGivenNonPendingOrder() public {
        // Setup
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        uint orderId_ = 1;

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        helper_createTestPaymentOrder(
            recipient_, amount_, orderId_, address(_token)
        );
        // Add payment order to queue, creating queue order
        helper_addPaymentOrderToQueue(order_, address(paymentClient));
        // Update order state to PROCESSED to test revert
        queue.exposed_updateOrderState(
            orderId_,
            address(paymentClient),
            IPP_Queue_v1.RedemptionState.PROCESSED
        );

        // Test function call
        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_InvalidState()")
        );
        queue.exposed_processNextOrder(address(paymentClient));
    }

    /* Test: function _processNextOrder()
        ├── Given queue is not empty
        ├── And the order state is PENDING
        └── And the payment client token balance is insufficient
            └── When the function _processNextOrder() is called
                └── Then it should return false
    */
    function testInternalProcessNextOrder_worksGivenInsufficientBalanceReturnsFalse(
    ) public {
        // Setup
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        uint orderId_ = 1;

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        helper_createTestPaymentOrder(
            recipient_, amount_, orderId_, address(_token)
        );
        // Add payment order to queue, creating queue order
        helper_addPaymentOrderToQueue(order_, address(paymentClient));

        // Test function call
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));

        // Post-assertions
        assertFalse(
            success_, "Processing should fail due to insufficient balance"
        );
    }

    /* Test: function _processNextOrder()
        ├── Given the order is valid
        └── And the payment client token balance is sufficient
            └── When the function _processNextOrder() is called
                └── Then it should return true
    */

    function testProcessNextOrder_worksGivenSufficientBalance() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        uint orderId_ = 1;
        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        helper_createTestPaymentOrder(
            recipient_, amount_, orderId_, address(_token)
        );
        // Mint tokens to payment client and approve PP Queue
        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);
        // Add payment order to queue, creating queue order
        helper_addPaymentOrderToQueue(order_, address(paymentClient));

        // Test function call
        bool success_ = queue.exposed_processNextOrder(address(paymentClient));

        // Post-assertions
        assertTrue(success_, "Processing should succeed");
    }

    /* Test testUpdateOrderState_RevertGivenInvalidTransition()
        └── Given a processed order
            └── When attempting to update to pending state
                └── Then it should revert with Module__PP_Queue_InvalidStateTransition
                    because orders cannot transition backwards from processed to pending.
    */
    function testUpdateOrderState_RevertGivenInvalidTransition() public {
        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;
        (bytes32 flags_, bytes32[] memory data_) =
            helper__encodePaymentOrderData(1);
        IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags_,
            data: data_
        });

        _token.mint(address(this), amount_);
        _token.approve(address(queue), amount_);
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(order_, address(this));

        // Command starts on PROCESSED (0), attempt to update to PENDING (2) should fail
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                orderId_,
                uint8(IPP_Queue_v1.RedemptionState.PROCESSED),
                uint8(IPP_Queue_v1.RedemptionState.PENDING)
            )
        );
        queue.exposed_updateOrderState(
            orderId_,
            address(paymentClient),
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    /* Test testValidQueueId_RevertGivenInvalidId()
        └── Given an invalid queue ID
            └── When validating ID
                └── Then it should return false.
    */
    function testValidQueueId_RevertGivenInvalidId() public {
        assertFalse(
            queue.exposed_validQueueId(999, address(this)),
            "Invalid queue ID should return false."
        );
    }

    /* Test testCancelPaymentOrder_RevertGivenNonExistentOrder()
        └── Given a non-existent order ID
            └── When cancelling order
                └── Then it should revert with Module__PP_Queue_InvalidOrderId.
    */
    function testCancelPaymentOrder_RevertGivenNonExistentOrder() public {
        uint nonExistentOrderId_ = 999;

        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                nonExistentOrderId_
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            nonExistentOrderId_, IERC20PaymentClientBase_v2(address(this))
        );
    }

    /* Test testCancelPaymentOrder_RevertGivenZeroId()
        └── Given order ID zero
            └── When cancelling order
                └── Then it should revert with Module__PP_Queue_InvalidOrderId.
    */
    function testCancelPaymentOrder_RevertGivenZeroId() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidOrderId(address,uint256)",
                address(this),
                0
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            0, IERC20PaymentClientBase_v2(address(this))
        );
    }

    /*
    Test: cancelPaymentOrderThroughQueueId
    └── Given: Caller is not permissioned
        └── When the function cancelPaymentOrderThroughQueueId() is called
            └── Then it should revert (modifier in place test)
    */
    function testCancelPaymentOrderThroughQueueId_ModifierInPlace() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        queue.cancelPaymentOrderThroughQueueId(
            0, IERC20PaymentClientBase_v2(address(0))
        );
    }

    /*    Test: function cancelPaymentOrderThroughQueueId()
        └── Given the canceledOrdeTreasury address is blacklisted
            └── When the function cancelPaymentOrderThroughQueueId() is called
                └── Then it should revert
    */
    function testCancelPaymentOrderThroughQueueId_RevertGivenBlacklistedCanceledOrdersTreasury(
        address recipient_,
        uint96 amount_
    ) public {
        // Setup
        recipient_ = helper_validPaymentReceiver(recipient_);
        vm.assume(amount_ > 0);
        uint queueId = 1;

        // Use non-standard token to blacklist canceledOrdersTreasury so the transfer
        // will fail and revert the function
        NonStandardTokenMock nonStandardToken = new NonStandardTokenMock();
        nonStandardToken.setFailTransferTo(canceledOrdersTreasury);

        // Create payment order
        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(
            recipient_, amount_, queueId, address(nonStandardToken)
        );
        // Mint tokens to payment client and approve PP Queue
        helper_setupPaymentTokenBalanceAndApproval(
            amount_, ERC20Mock(address(nonStandardToken))
        );

        // Get value for pre-assertions
        uint orderId_ =
            helper_addPaymentOrderToQueue(order, address(paymentClient));
        uint queueSize_ = queue.getQueueSizeForClient(address(paymentClient));
        IPP_Queue_v1.QueuedOrder memory queuedOrder_ = queue.getOrder(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );

        // pre-assertions
        assertEq(
            uint(queuedOrder_.state_),
            uint(IPP_Queue_v1.RedemptionState.PENDING)
        );
        assertEq(nonStandardToken.balanceOf(recipient_), 0);
        assertEq(nonStandardToken.balanceOf(address(paymentClient)), amount_);
        assertEq(queueSize_, 1);

        // Test
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module_PP_Queue_PaymentFailed(address,address,address,uint256)",
                address(paymentClient),
                canceledOrdersTreasury,
                address(nonStandardToken),
                amount_
            )
        );
        queue.cancelPaymentOrderThroughQueueId(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test testPublicCancelPayments_failsGivenNonModuleCaller() function
        ├── Given a caller that is not a module
        │   └── When cancelRunningPayments is called
        │       └── Then the transaction should revert with "Module__PP_Queue_OnlyCallableByClient()"
    */
    function testPublicCancelPayments_failsGivenNonModuleCaller(
        address nonModule
    ) public {
        vm.assume(nonModule != address(queue));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_OnlyCallableByClient()")
        );
        queue.cancelRunningPayments(paymentClient);
    }

    /* Test testPublicProcessPayments_succeedsGivenValidSetupAndPaymentOrder() function
        ├── Given a valid payment setup
        │   └── And a payment order has been queued
        │       └── When processPayments is called
        │           └── Then the recipient should receive tokens
        │           └── And the queue should have no tokens left
        │           └── And the payment client should have no tokens left
    */
    function testPublicProcessPayments_succeedsGivenValidSetupAndPaymentOrder()
        public
    {
        // Setup payment client with orders
        address recipient = makeAddr("recipient");
        uint96 amount = 1000;

        IERC20PaymentClientBase_v2.PaymentOrder memory orders =
            helper_createTestPaymentOrder(recipient, amount, 1, address(_token));
        // Setup initial state
        _token.mint(address(paymentClient), amount);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount);

        // Add payment order to queue
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(orders, address(paymentClient));
        vm.stopPrank();

        // Call processPayments as the module to add to queue
        vm.prank(address(paymentClient));
        queue.processPayments(paymentClient);

        // Verify final state
        assertEq(
            _token.balanceOf(recipient),
            amount,
            "Recipient should receive tokens"
        );

        assertEq(
            _token.balanceOf(address(queue)), 0, "Queue should have no tokens"
        );
        assertEq(
            _token.balanceOf(address(paymentClient)),
            0,
            "Payment client should have no tokens"
        );

        helper_assertOrderMatch(
            orderId_,
            address(paymentClient),
            recipient,
            amount,
            IPP_Queue_v1.RedemptionState.PROCESSED
        );
    }

    /* Test testPublicProcessAndCancelPayments_succeedsGivenValidSetupAndPaymentOrder() function
        ├── Given a valid payment setup
        │   └── And a payment order has been queued
        │       └── When processPayments is called
        │           └── And then cancelPaymentOrderThroughQueueId is attempted
        │               └── Then the recipient should receive tokens
        │               └── And the queue should have no tokens left
        │               └── And the payment client should have no tokens left
        │               └── And attempting to cancel should revert with "Module__PP_Queue_InvalidState()"
    */
    function testPublicProcessAndCancelPayments_succeedsGivenValidSetupAndPaymentOrder(
    ) public {
        // Setup payment client with orders
        address recipient = makeAddr("recipient");
        uint96 amount = 1000;

        IERC20PaymentClientBase_v2.PaymentOrder memory orders =
            helper_createTestPaymentOrder(recipient, amount, 1, address(_token));

        // Setup initial state
        _token.mint(address(paymentClient), amount);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(_token), amount
        );
        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount);

        // Add payment order to queue
        uint orderId_ =
            queue.exposed_addPaymentOrderToQueue(orders, address(paymentClient));
        vm.stopPrank();

        // Call processPayments as the module to add to queue
        vm.prank(address(paymentClient));
        queue.processPayments(paymentClient);
        //processprocessPayments and executePaymentQueue

        // Verify final state
        assertEq(
            _token.balanceOf(recipient),
            amount,
            "Recipient should receive tokens"
        );

        assertEq(
            _token.balanceOf(address(queue)), 0, "Queue should have no tokens"
        );
        assertEq(
            _token.balanceOf(address(paymentClient)),
            0,
            "Payment client should have no tokens"
        );

        helper_assertOrderMatch(
            orderId_,
            address(paymentClient),
            recipient,
            amount,
            IPP_Queue_v1.RedemptionState.PROCESSED
        );

        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_InvalidState()")
        );

        vm.prank(address(this));
        queue.cancelPaymentOrderThroughQueueId(
            orderId_, IERC20PaymentClientBase_v2(address(paymentClient))
        );
    }

    /* Test claimPreviouslyUnclaimableToTreasury 
        └── Given caller is not permissioned
            └── When claimPreviouslyUnclaimableToTreasury is called
                └── Then it should revert (modifier in place test)
    */
    function testClaimPreviouslyUnclaimableToTreasury_modifierInPlace()
        public
    {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        queue.claimPreviouslyUnclaimableToTreasury(
            address(0), address(0), address(0)
        );
    }

    /* Test testPublicClaimPreviouslyUnclaimableToTreasury_succeedsGivenValidConditions() function
        ├── Given an unclaimable payment order has been added
        │   └── And tokens have been transferred to the queue
        │       └── When claimPreviouslyUnclaimableToTreasury is called by an permissioned caller
        │           └── Then the unclaimable amount should be zero
        │           └── And the tokens should be transferred to the failed orders treasury
        │           └── And the canceled orders treasury should not receive any tokens
    */
    function testPublicClaimPreviouslyUnclaimableToTreasury_succeedsGivenValidConditions(
    ) public {
        paymentClient.exposed_addToOutstandingTokenAmounts(address(_token), 200);

        address recipient_ = makeAddr("recipient");
        uint96 amount_ = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory order =
        helper_createTestPaymentOrder(recipient_, amount_, 1, address(_token));

        _token.mint(address(paymentClient), amount_ * 2);

        vm.startPrank(address(paymentClient));
        _token.approve(address(queue), amount_ * 2);
        queue.exposed_addUnclaimableOrder(order, address(paymentClient));
        _token.transfer(address(queue), amount_);
        vm.stopPrank();

        vm.prank(address(queue));
        _token.approve(address(queue), amount_);

        vm.prank(address(this));
        queue.claimPreviouslyUnclaimableToTreasury(
            address(paymentClient), address(_token), recipient_
        );

        assertEq(
            queue.unclaimable(
                address(paymentClient), address(_token), recipient_
            ),
            0,
            "Unclaimable amount should be zero after claiming"
        );

        assertEq(
            _token.balanceOf(queue.getFailedOrdersTreasury()),
            amount_,
            "Treasury should have received the tokens"
        );

        assertEq(
            _token.balanceOf(queue.getCanceledOrdersTreasury()),
            0,
            "Canceled orders treasury should not receive any tokens"
        );
    }

    /* Test testPublicSetCanceledOrdersTreasury
        ├── Given a new treasury address
        │   └── And the current treasury address is different
        │       └── When setCanceledOrdersTreasury is called by non permissioned caller
        │           └── Then it should revert (Modifier in place test)
        │       └── And when called by a permissioned caller
        │           └── Then the treasury address should be updated
    */

    function testPublicSetCanceledOrdersTreasury_ModifierInPosition() public {
        //permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        queue.setCanceledOrdersTreasury(address(0));
    }

    function testPublicSetCanceledOrdersTreasury_succeedsGivenAuthorizedCaller()
        public
    {
        address newTreasury = makeAddr("newTreasury");

        assertNotEq(
            queue.getCanceledOrdersTreasury(),
            newTreasury,
            "New treasury should be different from current"
        );

        queue.setCanceledOrdersTreasury(newTreasury);

        assertEq(
            queue.getCanceledOrdersTreasury(),
            newTreasury,
            "Treasury address should be updated"
        );
    }

    /* Test testPublicSetFailedOrdersTreasury
        ├── Given a new failed orders treasury address
        │   └── And the current failed orders treasury address is different
        │       └── When setFailedOrdersTreasury is called by a permissioned caller
        │           └── Then it should revert (Modifier in place test)
        │       └── And when called by a permissioned caller 
        │           └── Then the failed orders treasury address should be updated
    */

    function testPublicSetFailedOrdersTreasury_ModifierInPosition() public {
        //permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        queue.setFailedOrdersTreasury(address(0));
    }

    function testPublicSetFailedOrdersTreasury_succeedsGivenAuthorizedCaller()
        public
    {
        address newTreasury = makeAddr("newFailedTreasury");

        assertNotEq(
            queue.getFailedOrdersTreasury(),
            newTreasury,
            "New treasury should be different from current"
        );

        vm.prank(address(this));
        queue.setFailedOrdersTreasury(newTreasury);

        assertEq(
            queue.getFailedOrdersTreasury(),
            newTreasury,
            "Failed orders treasury should be updated"
        );
    }

    /* Test testPublicValidPaymentOrder_succeedsGivenValidConditions() function
        ├── Given a valid payment order
        │   └── Then validPaymentOrder should return true
        ├── Given an invalid payment order with zero recipient address
        │   └── Then validPaymentOrder should return false
        ├── Given an invalid payment order with zero amount
        │   └── Then validPaymentOrder should return false
        └── Given an invalid payment order with zero token address
            └── Then validPaymentOrder should return false
    */
    function testPublicValidPaymentOrder_succeedsGivenValidConditions()
        public
    {
        address recipient = makeAddr("recipient");
        uint96 amount = 100;
        IERC20PaymentClientBase_v2.PaymentOrder memory validOrder =
            helper_createTestPaymentOrder(recipient, amount, 1, address(_token));

        assertTrue(
            queue.validPaymentOrder(validOrder),
            "Valid payment order should return true"
        );

        IERC20PaymentClientBase_v2.PaymentOrder memory invalidOrder =
        helper_createTestPaymentOrder(address(0), amount, 1, address(_token));

        assertFalse(
            queue.validPaymentOrder(invalidOrder),
            "Payment order with zero address recipient should return false"
        );

        invalidOrder =
            helper_createTestPaymentOrder(recipient, 0, 1, address(_token));

        assertFalse(
            queue.validPaymentOrder(invalidOrder),
            "Payment order with zero amount should return false"
        );

        invalidOrder = validOrder;
        invalidOrder.paymentToken = address(0);

        assertFalse(
            queue.validPaymentOrder(invalidOrder),
            "Payment order with zero token address should return false"
        );
    }

    /* Test: Function _getProtocolFeeDetails()
        └── Given valid protocol fee amount
            ├── And the collectProtocolFee flag is true
            │   └── When the function _getProtocolFeeDetails() is called
            │       └── Then it should return the correct fee amount and treasury address
            └── And the collectProtocolFee flag is false
                └── When the function _getProtocolFeeDetails() is called
                    └── Then it should return 0 for the fee and total amount as net amount
    */

    function testInternalGetProtocolFeeAmountAndTreasury_worksGivenCorrectFeeDetailsRetrieved(
        uint protocolFee_,
        uint totalAmount_
    ) public {
        protocolFee_ = bound(protocolFee_, 1, feeManager.maxFee());
        totalAmount_ = bound(totalAmount_, 1e18, type(uint128).max);
        bool collectProtocolFee_ = true;

        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(queue),
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            true,
            protocolFee_
        );

        uint expectedFeeAmount = totalAmount_ * protocolFee_ / BPS;
        address expectedTreasury =
            feeManager.getWorkflowTreasuries(address(_orchestrator));

        (uint feeAmount, uint netAmount, address treasury) = queue
            .exposed_getProtocolFeeDetails(
            totalAmount_,
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            collectProtocolFee_
        );

        assertEq(feeAmount, expectedFeeAmount, "Fee amount should be correct");
        assertEq(
            netAmount, totalAmount_ - feeAmount, "Net amount should be correct"
        );
        assertEq(treasury, expectedTreasury, "Treasury should be correct");
    }

    function testInternalGetProtocolFeeAmountAndTreasury_worksGivenNoFee(
        uint totalAmount_
    ) public {
        totalAmount_ = bound(totalAmount_, 1e18, type(uint128).max);
        bool collectProtocolFee_ = false;

        (uint feeAmount, uint netAmount, address treasury) = queue
            .exposed_getProtocolFeeDetails(
            totalAmount_,
            PROCESS_PAYMENTS_FUNCTION_SELECTOR,
            collectProtocolFee_
        );

        assertEq(feeAmount, 0, "Fee amount should be 0");
        assertEq(netAmount, totalAmount_, "Net amount should be correct");
        assertEq(treasury, address(0), "Treasury should be 0 address");
    }

    /* Test testValidChainId_GivenValidAndInvalidIds()
        └── Given chain IDs
            └── When validating chain IDs
                ├── Then current chain ID should return true
                ├── Then different chain ID should return false
                └── Then zero chain ID should return false
    */

    function testInternalValidChainId_RevertsGivenInvalidIds(uint chainId_)
        public
    {
        chainId_ = bound(chainId_, 0, type(uint128).max);

        // Test different chain ID
        vm.assume(chainId_ != block.chainid);
        assertFalse(
            queue.exposed_validChainId(chainId_),
            "Different chain ID should be invalid"
        );

        // Test zero chain ID
        assertFalse(
            queue.exposed_validChainId(0), "Zero chain ID should be invalid"
        );
    }

    /* Test testValidChainId_GivenInvalidChainId()
        └── Given an invalid chain ID
            └── When validating the chain ID
                └── Then it should revert
    */
    function testInternalValidChainId_worksGivenValidChainId() public {
        // Test current chain ID
        assertTrue(
            queue.exposed_validChainId(block.chainid),
            "Current chain ID should be valid"
        );
    }

    /* Test function _lowLevelTransfer()
        └── Given valid transfer inputs
            └── When the function _lowLevelTransfer() is called
                └── Then the transfer should succeed         
    */
    function testInternalLowLevelTransfer_worksGivenValidInputsReturnsTrue(
        address recipient_,
        uint96 amount_
    ) public {
        // Validate inputs
        recipient_ = helper_validPaymentReceiver(recipient_);
        amount_ = uint96(bound(amount_, 1, type(uint96).max));

        // Setup
        helper_setupPaymentTokenBalanceAndApproval(amount_, _token);

        // pre-assertions
        assertEq(
            _token.balanceOf(address(paymentClient)),
            amount_,
            "Payment client should have the correct balance"
        );
        assertEq(
            _token.balanceOf(recipient_), 0, "Recipient should have no balance"
        );

        // Test function call
        bool success = queue.exposed_lowLevelTransfer(
            address(_token), address(paymentClient), recipient_, amount_
        );

        // Post-assertions
        assertTrue(success, "Transfer should succeed");
        assertEq(
            _token.balanceOf(recipient_),
            amount_,
            "Recipient should receive amount"
        );
        assertEq(
            _token.balanceOf(address(paymentClient)),
            0,
            "Client balance should be zero"
        );
    }

    /* Test: function _lowLevelTransfer()
        └── Given recipent is blacklisted
            └── When the function _lowLevelTransfer() is called
                └── Then the transfer should fail
    */
    function testInternalLowLevelTransfer_worksGivenBlacklistedRecipientReturnsFalse(
        address recipient_,
        uint96 amount_
    ) public {
        // Validate inputs
        recipient_ = helper_validPaymentReceiver(recipient_);
        amount_ = uint96(bound(amount_, 1, type(uint96).max));

        // Setup
        NonStandardTokenMock blacklistingToken = new NonStandardTokenMock();
        blacklistingToken.setFailTransferTo(recipient_);
        blacklistingToken.mint(address(paymentClient), amount_);
        blacklistingToken.approve(address(queue), amount_);

        // Test function call
        bool success = queue.exposed_lowLevelTransfer(
            address(blacklistingToken),
            address(paymentClient),
            recipient_,
            amount_
        );

        // Post-assertions
        assertFalse(success, "Transfer should fail");
    }

    /* Test testLowLevelTransfer_GivenInvalidToken()
        └── Given invalid token contracts
            └── When performing low level transfer
                ├── Then non-ERC20 contract should fail
                └── Then invalid transfer contract should fail
    */
    function testInternalLowLevelTransfer_worksGivenInvalidTokenReturnsFalse()
        public
    {
        // Setup
        address recipient = makeAddr("recipient");
        uint amount = 100;
        address invalidToken = makeAddr("invalidToken");

        // Test function call
        bool success = queue.exposed_lowLevelTransfer(
            invalidToken, address(paymentClient), recipient, amount
        );

        // Post-assertions
        assertFalse(success, "Transfer should fail with non-ERC20 contract");
    }

    /* Test testEnsureValidClient_GivenValidClient()
        └── Given a valid client address that is:
            ├── Not address(0)
            ├── Not queue address
            └── Not orchestrator address
                └── When caller is the client
                    └── Then it should succeed
    */
    function testInternalEnsureValidClient_worksGivenValidClient(
        address client_
    ) public {
        vm.assume(client_ != address(0));
        vm.assume(client_ != address(queue));
        vm.assume(client_ != address(_orchestrator));
        vm.assume(client_ != address(this));

        vm.prank(client_);
        queue.exposed_ensureValidClient(client_);
    }

    /* Test testEnsureValidClient_RevertGivenInvalidClient()
        └── Given an invalid client address
            └── When checking client validity
                ├── Then it should revert with Module__PP_Queue_InvalidClientAddress for zero address
                └── Then it should revert with Module__PP_Queue_InvalidClientAddress for queue address
    */
    function testInternalEnsureValidClient_RevertGivenInvalidClient() public {
        vm.expectRevert();
        queue.exposed_ensureValidClient(address(0));

        vm.expectRevert();

        queue.exposed_ensureValidClient(address(queue));
    }

    /* Test testEnsureValidClient_RevertGivenNonClientCaller()
        └── Given a valid client address
            └── When caller is not the client
                └── Then it should revert with Module__PP_Queue_OnlyCallableByClient
    */
    function testInternalEnsureValidClient_RevertGivenNonClientCaller(
        address client_,
        address caller_
    ) public {
        vm.assume(client_ != address(0));
        vm.assume(client_ != address(queue));
        vm.assume(client_ != address(_orchestrator));
        vm.assume(client_ != caller_);
        vm.assume(caller_ != address(0));

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSignature("Module__PP_Queue_OnlyCallableByClient()")
        );
        queue.exposed_ensureValidClient(client_);
    }

    /* Test testSetCanceledOrdersTreasury_GivenValidAddress()
        └── Given a valid treasury address
            └── When setting the canceled orders treasury
                └── Then it should be set correctly
    */
    function testInternalSetCanceledOrdersTreasury_worksGivenValidAddress()
        public
    {
        address newTreasury = makeAddr("newTreasury");

        queue.exposed_setCanceledOrdersTreasury(newTreasury);

        // Verify the treasury was set correctly by checking the queue's state
        assertEq(
            queue.getCanceledOrdersTreasury(),
            newTreasury,
            "Canceled orders treasury should be updated"
        );
    }

    /* Test testSetCanceledOrdersTreasury_RevertGivenZeroAddress()
        └── Given a zero address
            └── When setting the canceled orders treasury
                └── Then it should revert
    */
    function testInternalSetCanceledOrdersTreasury_RevertGivenZeroAddress()
        public
    {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidTreasuryAddress(address)", address(0)
            )
        );
        queue.exposed_setCanceledOrdersTreasury(address(0));
    }

    /* Test testSetFailedOrdersTreasury_GivenValidAddress()
        └── Given a valid treasury address
            └── When setting the failed orders treasury
                └── Then it should be set correctly
    */
    function testInternalSetFailedOrdersTreasury_worksGivenValidAddress()
        public
    {
        address newTreasury = makeAddr("newTreasury");

        queue.exposed_setFailedOrdersTreasury(newTreasury);

        // Verify the treasury was set correctly by checking the queue's state
        assertEq(
            queue.getFailedOrdersTreasury(),
            newTreasury,
            "Failed orders treasury should be updated"
        );
    }

    /* Test testSetFailedOrdersTreasury_RevertGivenZeroAddress()
        └── Given a zero address
            └── When setting the failed orders treasury
                └── Then it should revert
    */
    function testInternalSetFailedOrdersTreasury_RevertGivenZeroAddress()
        public
    {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidTreasuryAddress(address)", address(0)
            )
        );
        queue.exposed_setFailedOrdersTreasury(address(0));
    }

    /* Test testEnsureValidPaymentToken_GivenValidToken()
        └── Given a valid payment token
            └── And the token is not address(0)
                └── Then it should return true
    */
    function testInternalEnsureValidPaymentToken_worksGivenValidToken()
        public
    {
        assertTrue(queue.exposed_validPaymentToken(address(_token)));
    }

    /* Test testEnsureValidPaymentToken_RevertGivenInvalidToken()
        └── Given an invalid payment token
            └── When ensuring valid payment token
                └── Then it should revert
    */
    function testInternalEnsureValidPaymentToken_RevertGivenInvalidToken()
        public
    {
        assertFalse(queue.exposed_validPaymentToken(address(0)));
    }

    /* Test testValidateFlagsAndData_GivenValidFlagsAndData()
        └── Given valid flags with ORDER_ID bit set
            └── And data array with order ID
                └── Then it should return true
    */
    function testInternalValidateFlagsAndData_worksGivenValidFlagsAndData()
        public
    {
        bytes32 flags = bytes32(uint(1)); // Set ORDER_ID bit
        bytes32[] memory data = new bytes32[](1);
        data[0] = bytes32(uint(123)); // Some order ID

        assertTrue(queue.exposed_validateFlagsAndData(flags, data));
    }

    /* Test testValidateFlagsAndData_GivenValidFlagsWithoutData()
        └── Given valid flags without ORDER_ID bit set
            └── And empty data array
                └── Then it should return true
    */
    function testInternalValidateFlagsAndData_worksGivenValidFlagsWithoutData()
        public
    {
        bytes32 flags = bytes32(uint(0)); // No bits set
        bytes32[] memory data = new bytes32[](0);

        assertFalse(queue.exposed_validateFlagsAndData(flags, data));
    }

    /* Test testValidateFlagsAndData_GivenInvalidFlagsWithData()
        └── Given flags with ORDER_ID bit set
            └── And empty data array
                └── Then it should return false
    */
    function testInternalValidateFlagsAndData_FailsGivenInvalidFlagsWithData()
        public
    {
        bytes32 flags = bytes32(uint(1)); // Set ORDER_ID bit
        bytes32[] memory data = new bytes32[](0); // Empty data array

        assertFalse(queue.exposed_validateFlagsAndData(flags, data));
    }

    /* Test testValidateFlagsAndData_GivenInvalidFlagsWithoutData()
        └── Given flags with invalid bits set
            └── And empty data array
                └── Then it should return false
    */
    function testInternalValidateFlagsAndData_FailsGivenInvalidFlagsWithoutData(
    ) public {
        bytes32 flags = bytes32(uint(2)); // Set invalid bit
        bytes32[] memory data = new bytes32[](0);

        assertFalse(queue.exposed_validateFlagsAndData(flags, data));
    }

    /* Test testValidStateTransition_RevertGivenInvalidTransition()
        └── Given an invalid state transition
            └── When validating the state transition
                └── Then it should revert with Module__PP_Queue_InvalidStateTransition
    */
    function testInternalValidStateTransition_RevertGivenInvalidTransition()
        public
    {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module__PP_Queue_InvalidStateTransition(uint256,uint8,uint8)",
                1,
                uint8(IPP_Queue_v1.RedemptionState.PROCESSED),
                uint8(IPP_Queue_v1.RedemptionState.PENDING)
            )
        );
        queue.exposed_validStateTransition(
            1,
            IPP_Queue_v1.RedemptionState.PROCESSED,
            IPP_Queue_v1.RedemptionState.PENDING
        );
    }

    /* Test testValidStateTransition_SucceedsGivenValidTransitions()
        └── Given valid state transitions
            └── When validating the state transitions
                └── Then they should succeed
    */
    function testInternalValidStateTransition_worksGivenValidTransitions()
        public
        view
    {
        // PENDING -> PROCESSED
        queue.exposed_validStateTransition(
            1,
            IPP_Queue_v1.RedemptionState.PENDING,
            IPP_Queue_v1.RedemptionState.PROCESSED
        );

        // PENDING -> CANCELLED
        queue.exposed_validStateTransition(
            1,
            IPP_Queue_v1.RedemptionState.PENDING,
            IPP_Queue_v1.RedemptionState.CANCELLED
        );

        // PENDING -> FAILED
        queue.exposed_validStateTransition(
            1,
            IPP_Queue_v1.RedemptionState.PENDING,
            IPP_Queue_v1.RedemptionState.FAILED
        );
    }

    /* Test testClaimPreviouslyUnclaimable_RevertGivenNoUnclaimableAmount()
        └── Given no unclaimable amount for the client/token/receiver combination
            └── When attempting to claim previously unclaimable amount
                └── Then it should revert with Module__PP_Queue_NoUnclaimableAmount
    */
    function testInternalClaimPreviouslyUnclaimable_RevertGivenNoUnclaimableAmount(
    ) public {
        address recipient = makeAddr("recipient");

        queue.exposed_claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), recipient
        );
        assertEq(
            _token.balanceOf(recipient),
            0,
            "Recipient should not receive any tokens"
        );
    }
    /* Test testClaimPreviouslyUnclaimable_SucceedsGivenUnclaimableAmount()
        └── Given unclaimable amount for the client/token/receiver combination
            └── When attempting to claim previously unclaimable amount
                └── Then it should succeed
    */

    function testInternalClaimPreviouslyUnclaimable_worksGivenUnclaimableAmount(
    ) public {
        address recipient = makeAddr("recipient");
        uint96 amount = 100;

        // Setup: give tokens to payment client and approve queue to spend them
        helper_setupPaymentTokenBalanceAndApproval(amount, _token);

        // Transfer tokens to the queue contract first (simulating failed payment flow)
        vm.prank(address(paymentClient));
        _token.transfer(address(queue), amount);

        // Queue needs to approve itself to transfer its own tokens
        vm.prank(address(queue));
        _token.approve(address(queue), amount);

        // Now add it as unclaimable
        queue.exposed_addUnclaimableOrder(
            helper_createTestPaymentOrder(recipient, amount, 1, address(_token)),
            address(paymentClient)
        );

        // Try to claim
        queue.exposed_claimPreviouslyUnclaimable(
            address(paymentClient), address(_token), recipient
        );

        assertEq(
            _token.balanceOf(recipient),
            amount,
            "Recipient should receive tokens"
        );
    }
    /* Test testValidPaymentOrder_RevertGivenInvalidTargetChain()
        └── Given a payment order with an invalid target chain
            └── When validating the payment order
                └── Then it should revert with Module__PP_Queue_InvalidTargetChain
    */

    function testInternalValidPaymentOrder_failsWithInvalidTargetChain()
        public
    {
        address recipient = makeAddr("recipient");
        uint96 amount = 100;
        (bytes32 flags, bytes32[] memory data) =
            helper__encodePaymentOrderData(1);

        IERC20PaymentClientBase_v2.PaymentOrder memory invalidOrder =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient,
            amount: amount,
            paymentToken: address(_token),
            originChainId: block.chainid,
            targetChainId: block.chainid + 1, // Invalid target chain
            flags: flags,
            data: data
        });

        assertFalse(
            queue.exposed_validPaymentOrder(invalidOrder),
            "Payment order with invalid target chain should return false"
        );
    }
    /* Test testValidPaymentOrder_SucceedsGivenValidOrder()
        └── Given a valid payment order
            └── When validating the payment order
                └── Then it should return true
    */

    function testInternalValidPaymentOrder_succeedsWithValidOrder() public {
        address recipient = makeAddr("recipient");
        uint96 amount = 100;

        IERC20PaymentClientBase_v2.PaymentOrder memory validOrder =
            helper_createTestPaymentOrder(recipient, amount, 1, address(_token));

        assertTrue(
            queue.exposed_validPaymentOrder(validOrder),
            "Payment order with valid target chain should return true"
        );
    }

    // ================================================================================
    // Helper Functions

    function helper_validPaymentReceiver(address recipient_)
        internal
        view
        returns (address)
    {
        vm.assume(
            recipient_ != address(0) && recipient_ != address(queue)
                && recipient_ != address(this) && recipient_ != address(_token)
                && recipient_ != address(_orchestrator)
                && recipient_ != address(paymentClient)
        );
        return recipient_;
    }

    function helper_createTestPaymentOrder(
        address recipient_,
        uint96 amount_,
        uint orderNum_,
        address token_
    ) internal view returns (IERC20PaymentClientBase_v2.PaymentOrder memory) {
        (bytes32 flags, bytes32[] memory data) =
            helper__encodePaymentOrderData(orderNum_);
        return IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            amount: amount_,
            paymentToken: address(token_),
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags,
            data: data
        });
    }

    function helper_addPaymentOrderToQueue(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_,
        address client_
    ) internal returns (uint queueId_) {
        queueId_ = queue.exposed_addPaymentOrderToQueue(order_, client_);
    }

    function helper_setupPaymentTokenBalanceAndApproval(
        uint96 amount_,
        ERC20Mock token_
    ) internal {
        token_.mint(address(paymentClient), amount_);
        paymentClient.exposed_addToOutstandingTokenAmounts(
            address(token_), amount_
        );
        vm.prank(address(paymentClient));
        token_.approve(address(queue), amount_);
    }

    function helper_assertOrderMatch(
        uint orderId_,
        address client_,
        address expectedRecipient_,
        uint96 expectedAmount_,
        IPP_Queue_v1.RedemptionState expectedState_
    ) internal {
        IPP_Queue_v1.QueuedOrder memory queuedOrder =
            queue.getOrder(orderId_, IERC20PaymentClientBase_v2(client_));
        assertEq(
            queuedOrder.order_.recipient, expectedRecipient_, "Wrong recipient"
        );
        assertEq(queuedOrder.order_.amount, expectedAmount_, "Wrong amount");
        assertEq(
            queuedOrder.order_.paymentToken, address(_token), "Wrong token"
        );
        assertEq(uint(queuedOrder.state_), uint(expectedState_), "Wrong state");
    }

    function helper__encodePaymentOrderData(uint orderId_)
        internal
        pure
        returns (bytes32 flags_, bytes32[] memory data_)
    {
        bytes32 _flags;
        _flags = 0;

        uint8[] memory flags = new uint8[](1); // The Module will use 1 flag
        flags[0] = 0;

        _flags |= bytes32((1 << flags[0]));

        bytes32[] memory paymentParameters = new bytes32[](1);
        paymentParameters[0] = bytes32(orderId_);

        return (_flags, paymentParameters);
    }

    function helper_setupLargeQueue(
        uint96 totalSellAmount_,
        uint numberOfOrders_
    ) internal {
        // Start Queue ID for adding the orders
        uint queueId = 1;

        // Max number of orders that can be processed in a single execution
        uint maxOrdersPerExecution = queue.getMaxOrdersPerExecution();

        // Amount of collateral to be redeemed for each order
        uint96 sellAmountForEachOrder =
            uint96(totalSellAmount_ / maxOrdersPerExecution);

        // Mint tokens to payment client and approve PP Queue
        helper_setupPaymentTokenBalanceAndApproval(totalSellAmount_, _token);

        vm.startPrank(address(paymentClient));
        for (uint i = 0; i < numberOfOrders_; i++) {
            address recipient_ =
                makeAddr(string.concat("recipient", vm.toString(i)));
            // Create payment order
            IERC20PaymentClientBase_v2.PaymentOrder memory order_ =
            helper_createTestPaymentOrder(
                recipient_, sellAmountForEachOrder, queueId, address(_token)
            );
            // Add order to queue
            queue.exposed_addPaymentOrderToQueue(order_, address(paymentClient));
            queueId++;
        }
        vm.stopPrank();
    }
}
