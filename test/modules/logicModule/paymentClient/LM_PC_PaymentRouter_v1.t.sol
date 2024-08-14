// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "forge-std/console.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import "@oz/utils/Strings.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// SuT
import {
    ILM_PC_PaymentRouter_v1,
    LM_PC_PaymentRouter_v1
} from "@lm/LM_PC_PaymentRouter_v1.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBase_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";
import {Module_v1, IModule_v1} from "src/modules/base/Module_v1.sol";

import {OrchestratorV1Mock} from
    "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";

import {PP_Simple_v1, IPaymentProcessor_v1} from "@pp/PP_Simple_v1.sol";

import {
    IFundingManager_v1,
    FundingManagerV1Mock
} from "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract LM_PC_PaymentRouter_v1_Test is ModuleTest {
    // SuT
    LM_PC_PaymentRouter_v1 paymentRouter;

    address paymentPusher_user = makeAddr("paymentPusher_user");

    // Mock PaymentOrder data
    address po_recipient = makeAddr("recipient");
    address po_paymentToken = address(_token);
    uint po_amount = 100;
    uint po_start = block.timestamp;
    uint po_cliff = 100;
    uint po_end = block.timestamp + 1000;

    // Events
    event PaymentOrderAdded(
        address indexed recipient, address indexed token, uint amount
    );

    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        address indexed token,
        uint amount,
        uint start,
        uint cliff,
        uint end
    );

    function setUp() public virtual {
        // Add Module to Mock Orchestrator_v1
        address impl = address(new LM_PC_PaymentRouter_v1());
        paymentRouter = LM_PC_PaymentRouter_v1(Clones.clone(impl));

        _setUpOrchestrator(paymentRouter);

        paymentRouter.init(_orchestrator, _METADATA, bytes(""));

        bytes32 roleId = _authorizer.generateRoleId(
            address(paymentRouter), paymentRouter.PAYMENT_PUSHER_ROLE()
        );

        _authorizer.grantRole(roleId, paymentPusher_user);
    }

    function testInit() public override(ModuleTest) {
        bytes32 roleId = _authorizer.generateRoleId(
            address(paymentRouter), paymentRouter.PAYMENT_PUSHER_ROLE()
        );

        assertEq(_authorizer.hasRole(roleId, paymentPusher_user), true);
        assertEq(
            _authorizer.checkRoleMembership(roleId, paymentPusher_user), true
        );

        vm.startPrank(address(paymentRouter));
        assertEq(_authorizer.checkForRole(roleId, paymentPusher_user), true);
        vm.stopPrank();
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentRouter.init(_orchestrator, _METADATA, bytes(""));
    }
}

/*
    test_pushPayment
    ├── When the caller doesn't have the PAYMENT_PUSHER_ROLE
    │   └── It should revert
    └── When the caller has the PAYMENT_PUSHER_ROLE
        ├── When the Payment Order is incorrect
        │   ├── When the recipient is incorrect
        │   │   └── It should revert with the corresponding error message
        │   ├── When the paymentToken is incorrect
        │   │   └── It should revert with the corresponding error message
        │   └── When the amount is incorrect
        │       └── It should revert with the corresponding error message
        └── When the Payment Order is correct
            ├── It should add the Payment Order to the array of Payment Orders
            ├── It should emit an event
            ├── It should call processPayments
            └── It should emit an event
    */
contract LM_PC_PaymentRouter_v1_Test_pushPayment is
    LM_PC_PaymentRouter_v1_Test
{
    function test_WhenTheCallerDoesntHaveThePAYMENT_PUSHER_ROLE(address caller)
        external
    {
        // It should revert
        _assumeValidAddress(caller);
        vm.assume(caller != paymentPusher_user);
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(paymentRouter), paymentRouter.PAYMENT_PUSHER_ROLE()
                ),
                caller
            )
        );
        paymentRouter.pushPayment(address(0), address(0), 0, 0, 0, 0);
        vm.stopPrank();
    }
}

/*
    pushPaymentBatched
    ├── When the caller doesn't have the PAYMENT_PUSHER_ROLE
    │   └── It should revert
    └── When the caller has the PAYMENT_PUSHER_ROLE
        ├── When the Payment Order arrays are incorrect
        │   ├── When the array lengths are mismatched
        │   │   └── It should revert with the corresponding error message
        │   └── When the paramaters of a specific PaymentOrder are incorrect
        │       └── It was tested upstream
        └── When the Payment Orders are correct
            ├── It should add all Payment Orders
            ├── It should emit an event for each Payment Order
            ├── It should call processPayments
            └── It should emit an event for each Payment Order
    */
contract LM_PC_PaymentRouter_v1_Test_pushPaymentBatched is
    LM_PC_PaymentRouter_v1_Test
{
    uint8 numOfOrders = 2;
    address[] recipients = new address[](2);
    address[] paymentTokens = new address[](2);
    uint[] amounts = new uint[](2);
    uint[] starts = new uint[](2);
    uint[] cliffs = new uint[](2);
    uint[] ends = new uint[](2);

    function setUp() public override {
        super.setUp();
        recipients[0] = po_recipient;
        recipients[1] = address(0xB0B);
        paymentTokens[0] = address(_token);
        paymentTokens[1] = address(_token);
        amounts[0] = po_amount;
        amounts[1] = po_amount * 2;
        starts[0] = po_start;
        starts[1] = po_start + 100;
        cliffs[0] = po_cliff;
        cliffs[1] = po_cliff + 100;
        ends[0] = po_end;
        ends[1] = po_end + 500;
    }

    modifier whenTheCallerHasThePAYMENT_PUSHER_ROLE() {
        vm.startPrank(paymentPusher_user);
        _;
    }

    function test_WhenTheCallerDoesntHaveThePAYMENT_PUSHER_ROLE(address caller)
        external
    {
        // It should revert
        _assumeValidAddress(caller);
        vm.assume(caller != paymentPusher_user);
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(paymentRouter), paymentRouter.PAYMENT_PUSHER_ROLE()
                ),
                caller
            )
        );
        paymentRouter.pushPaymentBatched(
            0, new address[](0), new address[](0), new uint[](0), 0, 0, 0
        );
        vm.stopPrank();
    }

    function test_WhenTheArrayLengthsAreMismatched()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
    {
        // It should revert with the corresponding error message

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__ArrayLengthMismatch
                    .selector
            )
        );
        paymentRouter.pushPaymentBatched(
            3, recipients, paymentTokens, amounts, po_start, po_cliff, po_end
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__ArrayLengthMismatch
                    .selector
            )
        );
        paymentRouter.pushPaymentBatched(
            2,
            new address[](0),
            paymentTokens,
            amounts,
            po_start,
            po_cliff,
            po_end
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__ArrayLengthMismatch
                    .selector
            )
        );
        paymentRouter.pushPaymentBatched(
            2, recipients, new address[](0), amounts, po_start, po_cliff, po_end
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__ArrayLengthMismatch
                    .selector
            )
        );
        paymentRouter.pushPaymentBatched(
            2,
            recipients,
            paymentTokens,
            new uint[](0),
            po_start,
            po_cliff,
            po_end
        );
    }

    function test_WhenTheParamatersOfASpecificPaymentOrderAreIncorrect()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
    {
        // It was tested upstream
    }

    function test_WhenThePaymentOrdersAreCorrect(uint8 _numOfOrders)
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
    {
        // It should add all Payment Orders
        // It should emit an event for each Payment Order
        // It should call processPayments
        // It should emit an event for each Payment Order

        address[] memory _recipients;
        address[] memory _paymentTokens;
        uint[] memory _amounts;
        uint _start;
        uint _cliff;
        uint _end;

        (_recipients, _paymentTokens, _amounts, _start, _cliff, _end) =
            _generateRandomValidOrders(_numOfOrders);

        uint paymentsTriggeredBefore =
            _paymentProcessor.processPaymentsTriggered();

        for (uint i = 0; i < _numOfOrders; i++) {
            vm.expectEmit(true, true, true, true);
            emit PaymentOrderAdded(
                _recipients[i], _paymentTokens[i], _amounts[i]
            );
        }
        vm.expectEmit(true, false, false, false);
        emit PaymentOrderProcessed(
            address(0), address(0), address(0), 0, 0, 0, 0
        ); // since we are using a mock.

        paymentRouter.pushPaymentBatched(
            _numOfOrders,
            _recipients,
            _paymentTokens,
            _amounts,
            _start,
            _cliff,
            _end
        );

        assertEq(
            _paymentProcessor.processPaymentsTriggered(),
            paymentsTriggeredBefore + 1
        );
    }

    function _generateRandomValidOrders(uint8 _numOfOrders)
        internal
        returns (
            address[] memory _recipients,
            address[] memory _paymentTokens,
            uint[] memory _amounts,
            uint _start,
            uint _cliff,
            uint _end
        )
    {
        _recipients = new address[](_numOfOrders);
        _paymentTokens = new address[](_numOfOrders);
        _amounts = new uint[](_numOfOrders);
        starts = new uint[](_numOfOrders);
        cliffs = new uint[](_numOfOrders);
        ends = new uint[](_numOfOrders);

        for (uint i = 0; i < _numOfOrders; i++) {
            _recipients[i] = makeAddr(Strings.toString(i));
            _paymentTokens[i] = makeAddr(Strings.toString(i + _numOfOrders));
            _amounts[i] = i * 100 + 1;
        }

        _start = block.timestamp;
        _cliff = 100;
        _end = block.timestamp + 1000;
    }
}
