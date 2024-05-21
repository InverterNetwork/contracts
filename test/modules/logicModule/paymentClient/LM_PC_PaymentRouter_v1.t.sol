// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "forge-std/console.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {Clones} from "@oz/proxy/Clones.sol";

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
    uint po_dueTo = block.timestamp + 1000;

    function setUp() public {
        //Add Module to Mock Orchestrator_v1
        address impl = address(new LM_PC_PaymentRouter_v1());
        paymentRouter = LM_PC_PaymentRouter_v1(Clones.clone(impl));

        _setUpOrchestrator(paymentRouter);


        paymentRouter.init(_orchestrator, _METADATA, bytes(""));

        //vm.prank(address(paymentRouter));
        _authorizer.grantRoleFromModule(
            paymentRouter.PAYMENT_PUSHER_ROLE(), paymentPusher_user
        );

        console.log(_authorizer.hasModuleRole(paymentRouter.PAYMENT_PUSHER_ROLE(), paymentPusher_user));
vm.prank(paymentPusher_user);
        console.log(_authorizer.hasModuleRole(paymentRouter.PAYMENT_PUSHER_ROLE(), paymentPusher_user));

    }

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {
        assertEq(_authorizer.hasModuleRole(paymentRouter.PAYMENT_PUSHER_ROLE(), paymentPusher_user), true);
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
contract LM_PC_PaymentRouter_v1_Test_pushPayment is LM_PC_PaymentRouter_v1_Test {
    function test_WhenTheCallerDoesntHaveThePAYMENT_PUSHER_ROLE(address caller) external {
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
        paymentRouter.pushPayment(
            address(0), address(0), 0, 0
        );
        vm.stopPrank();

    }

    modifier whenTheCallerHasThePAYMENT_PUSHER_ROLE() {
        vm.startPrank(paymentPusher_user);
        _;
    }

    modifier whenThePaymentOrderIsIncorrect() {
        _;
    }

    function test_WhenTheRecipientIsIncorrect()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
        whenThePaymentOrderIsIncorrect
    {   
        // It should revert with the corresponding error message
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v1.Module__ERC20PaymentClientBase__InvalidRecipient.selector
            )
        );
        paymentRouter.pushPayment(
            address(0), po_paymentToken, po_amount, po_dueTo
        );
    }

    function test_WhenThePaymentTokenIsIncorrect()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
        whenThePaymentOrderIsIncorrect
    {
        // It should revert with the corresponding error message
    }

    function test_WhenTheAmountIsIncorrect()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
        whenThePaymentOrderIsIncorrect
    {
        // It should revert with the corresponding error message
    }

    function test_WhenThePaymentOrderIsCorrect()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
    {
        // It should add the Payment Order to the array of Payment Orders
        // It should emit an event
        // It should call processPayments
        // It should emit an event
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
    contract LM_PC_PaymentRouter_v1_Test_pushPaymentBatched is LM_PC_PaymentRouter_v1_Test{
    function test_WhenTheCallerDoesntHaveThePAYMENT_PUSHER_ROLE(address caller) external {
        // It should revert
        _assumeValidAddress(caller);
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
        paymentRouter.pushPayment(
            address(0), address(0), 0, 0
        );
                vm.stopPrank();

    }

    modifier whenTheCallerHasThePAYMENT_PUSHER_ROLE() {
        _;
    }

    modifier whenThePaymentOrderArraysAreIncorrect() {
        _;
    }

    function test_WhenTheArrayLengthsAreMismatched()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
        whenThePaymentOrderArraysAreIncorrect
    {
        // It should revert with the corresponding error message
    }

    function test_WhenTheParamatersOfASpecificPaymentOrderAreIncorrect()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
        whenThePaymentOrderArraysAreIncorrect
    {
        // It was tested upstream
    }

    function test_WhenThePaymentOrdersAreCorrect()
        external
        whenTheCallerHasThePAYMENT_PUSHER_ROLE
    {
        // It should add all Payment Orders
        // It should emit an event for each Payment Order
        // It should call processPayments
        // It should emit an event for each Payment Order
    }
}


