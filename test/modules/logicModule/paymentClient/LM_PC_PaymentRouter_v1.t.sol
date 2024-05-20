// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// SuT
import {ILM_PC_PaymentRouter_v1,LM_PC_PaymentRouter_v1} from
    "@lm/LM_PC_PaymentRouter_v1.sol";
import {IERC20PaymentClientBase_v1, ERC20PaymentClientBase_v1} from
    "@lm/abstracts/ERC20PaymentClientBase_v1.sol";
import {Module_v1, IModule_v1} from "src/modules/base/Module_v1.sol";

import {OrchestratorV1Mock} from
    "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";

import {
    PP_Simple_v1,
    IPaymentProcessor_v1
} from "@pp/PP_Simple_v1.sol";

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


        function setUp() public {
        //Add Module to Mock Orchestrator_v1
        address impl = address(new LM_PC_PaymentRouter_v1());
        paymentRouter = LM_PC_PaymentRouter_v1(Clones.clone(impl));

        _setUpOrchestrator(paymentRouter);

        //_authorizer.setIsAuthorized(address(this), true);
        _authorizer.grantRoleFromModule(paymentRouter.PAYMENT_PUSHER_ROLE(), address(this));


        paymentRouter.init(_orchestrator, _METADATA, bytes(""));
    }

        //This function also tests all the getters
    function testInit() public override(ModuleTest) {}

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentRouter.init(_orchestrator, _METADATA, bytes(""));
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
        │   └── It should emit an event
        └── It should call processPayments
            └── It should emit an event
*/


/*
pushPaymentBatched
├── When the caller doesn't have the PAYMENT_PUSHER_ROLE
│   └── It should revert
└── When the caller has the PAYMENT_PUSHER_ROLE
    ├── When the Payment Order arrays are incorrect
    │   ├── When the array lengths are mismatched
    │   │   └── It should revert with the corresponding error message
    │   └── When the paramaters of a specific PaymentOrder are incorrect
    │       └── Tested upstream
    └── When the Payment Orders are correct
        ├── It should add all Payment Orders
        │   └── It should emit events for each Payment Order
        └── It should call processPayments
            └── It should emit events for each Payment Order
*/

}
