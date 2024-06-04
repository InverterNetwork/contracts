// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// SuT
import {
    PP_Simple_v1,
    IPaymentProcessor_v1
} from "src/modules/paymentProcessor/PP_Simple_v1.sol";

// Mocks
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_SimpleV1Test is ModuleTest {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // SuT
    PP_Simple_v1 paymentProcessor;

    // Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;

    //--------------------------------------------------------------------------
    // Events
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint createdAt,
        uint dueTo
    );
    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );
    event UnclaimableAmountAdded(
        address indexed paymentClient, address indexed recipient, uint amount
    );

    function setUp() public {
        address impl = address(new PP_Simple_v1());
        paymentProcessor = PP_Simple_v1(Clones.clone(impl));

        _setUpOrchestrator(paymentProcessor);

        _authorizer.setIsAuthorized(address(this), true);

        paymentProcessor.init(_orchestrator, _METADATA, bytes(""));

        impl = address(new ERC20PaymentClientBaseV1Mock());
        paymentClient = ERC20PaymentClientBaseV1Mock(Clones.clone(impl));

        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));

        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(paymentProcessor.token()), address(_token));
    }

    function testSupportsInterface() public {
        assertTrue(
            paymentProcessor.supportsInterface(
                type(IPaymentProcessor_v1).interfaceId
            )
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, bytes(""));
    }

    function testInit2SimplePaymentProcessor() public {
        // Attempting to call the init2 function with malformed data
        // SHOULD FAIL
        vm.expectRevert(
            IModule_v1.Module__NoDependencyOrMalformedDependencyData.selector
        );
        paymentProcessor.init2(_orchestrator, abi.encode(123));

        // Calling init2 for the first time with no dependency
        // SHOULD FAIL
        bytes memory dependencyData = abi.encode(hasDependency, dependencies);
        vm.expectRevert(
            IModule_v1.Module__NoDependencyOrMalformedDependencyData.selector
        );
        paymentProcessor.init2(_orchestrator, dependencyData);

        // Calling init2 for the first time with dependency = true
        // SHOULD PASS
        dependencyData = abi.encode(true, dependencies);
        paymentProcessor.init2(_orchestrator, dependencyData);

        // Attempting to call the init2 function again.
        // SHOULD FAIL
        vm.expectRevert(IModule_v1.Module__CannotCallInit2Again.selector);
        paymentProcessor.init2(_orchestrator, dependencyData);
    }

    //--------------------------------------------------------------------------
    // Test: Payment Processing

    function testProcessPayments(
        address recipient,
        uint amount,
        bool paymentsFail
    ) public {
        vm.assume(recipient != address(paymentProcessor));
        vm.assume(recipient != address(paymentClient));
        vm.assume(recipient != address(0));
        vm.assume(amount != 0);

        // Add payment order to client.
        paymentClient.addPaymentOrder(
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipient,
                amount: amount,
                createdAt: block.timestamp,
                dueTo: block.timestamp
            })
        );

        if (paymentsFail) {
            // transfers will fail by returning false now
            _token.toggleReturnFalse();
        }

        vm.expectEmit(true, true, true, true);
        emit PaymentOrderProcessed(
            address(paymentClient),
            recipient,
            amount,
            block.timestamp,
            block.timestamp
        );
        if (!paymentsFail) {
            vm.expectEmit(true, true, true, true);
            emit TokensReleased(recipient, address(_token), amount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit UnclaimableAmountAdded(
                address(paymentClient), recipient, amount
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);

        //If call doesnt fail
        if (!paymentsFail) {
            // Check correct balances.
            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(_token.balanceOf(address(paymentClient)), 0);

            assertEq(amount, paymentClient.amountPaidCounter());
            assertEq(
                paymentProcessor.unclaimable(address(paymentClient), recipient),
                0
            );
        } //If call fails
        else {
            assertEq(0, paymentClient.amountPaidCounter());
            assertEq(
                paymentProcessor.unclaimable(address(paymentClient), recipient),
                amount
            );
        }
    }

    function testProcessPaymentsFailsWhenCalledByNonModule(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__OnlyCallableByModule
                    .selector
            )
        );
        paymentProcessor.processPayments(paymentClient);
    }

    function testProcessPaymentsFailsWhenCalledOnOtherClient(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        ERC20PaymentClientBaseV1Mock otherERC20PaymentClient =
            new ERC20PaymentClientBaseV1Mock();

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.processPayments(otherERC20PaymentClient);
    }

    function testCancelPaymentsFailsWhenCalledByNonModule(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__OnlyCallableByModule
                    .selector
            )
        );
        paymentProcessor.cancelRunningPayments(paymentClient);
    }

    function testCancelPaymentsFailsWhenCalledOnOtherClient(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(paymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorV1Mock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        ERC20PaymentClientBaseV1Mock otherERC20PaymentClient =
            new ERC20PaymentClientBaseV1Mock();

        vm.prank(address(paymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.cancelRunningPayments(otherERC20PaymentClient);
    }

    function testClaimPreviouslyUnclaimable(address[] memory recipients)
        public
    {
        vm.assume(recipients.length < 30);

        for (uint i = 0; i < recipients.length; i++) {
            //If recipient is invalid change it
            if (recipients[i] == address(0) || recipients[i].code.length != 0) {
                recipients[i] = address(0x1);
            }
        }

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // Add payment order to client and call processPayments.

        for (uint i = 0; i < recipients.length; i++) {
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    amount: 1,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp
                })
            );
        }
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // transfers will not fail anymore
        _token.toggleReturnFalse();

        uint amount;
        address recipient;
        uint amountPaid;
        for (uint i = 0; i < recipients.length; i++) {
            recipient = recipients[i];

            //Check that recipients are not handled twice
            //In case that the random array did it multiple times
            if (recipientsHandled[recipient]) continue;
            recipientsHandled[recipient] = true;

            amount =
                paymentProcessor.unclaimable(address(paymentClient), recipient);

            //Do call
            vm.expectEmit(true, true, true, true);
            emit TokensReleased(recipient, address(_token), amount);

            vm.prank(recipient);
            paymentProcessor.claimPreviouslyUnclaimable(
                address(paymentClient), recipient
            );

            assertEq(
                paymentProcessor.unclaimable(address(paymentClient), recipient),
                0
            );

            //Amount send
            assertEq(_token.balanceOf(recipient), amount);

            //Check that amountPaid is correct in PaymentClient
            amountPaid += amount;
            assertEq(paymentClient.amountPaidCounter(), amountPaid);
        }
    }

    mapping(address => bool) recipientsHandled;

    function testClaimPreviouslyUnclaimableFailsIfNothingToClaim() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor_v1
                    .Module__PaymentProcessor__NothingToClaim
                    .selector,
                address(paymentClient),
                address(this)
            )
        );
        paymentProcessor.claimPreviouslyUnclaimable(
            address(paymentClient), address(0x1)
        );
    }
}
