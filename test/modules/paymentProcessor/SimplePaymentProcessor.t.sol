// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// SuT
import {
    SimplePaymentProcessor,
    IPaymentProcessor
} from "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

// Mocks
import {
    IERC20PaymentClient,
    ERC20PaymentClientMock
} from "test/utils/mocks/modules/mixins/ERC20PaymentClientMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract SimplePaymentProcessorTest is ModuleTest {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // SuT
    SimplePaymentProcessor paymentProcessor;

    // Mocks
    ERC20PaymentClientMock ERC20PaymentClient = new ERC20PaymentClientMock(_token);

    function setUp() public {
        address impl = address(new SimplePaymentProcessor());
        paymentProcessor = SimplePaymentProcessor(Clones.clone(impl));

        _setUpProposal(paymentProcessor);

        _authorizer.setIsAuthorized(address(this), true);

        _proposal.addModule(address(ERC20PaymentClient));

        paymentProcessor.init(_proposal, _METADATA, bytes(""));

        ERC20PaymentClient.setIsAuthorized(address(paymentProcessor), true);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(paymentProcessor.token()), address(_token));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        paymentProcessor.init(_proposal, _METADATA, bytes(""));
    }

    function testInit2SimplePaymentProcessor() public {
        // Attempting to call the init2 function with malformed data
        // SHOULD FAIL
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        paymentProcessor.init2(_proposal, abi.encode(123));

        // Calling init2 for the first time with no dependency
        // SHOULD FAIL
        bytes memory dependencydata = abi.encode(hasDependency, dependencies);
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        paymentProcessor.init2(_proposal, dependencydata);

        // Calling init2 for the first time with dependency = true
        // SHOULD PASS
        dependencydata = abi.encode(true, dependencies);
        paymentProcessor.init2(_proposal, dependencydata);

        // Attempting to call the init2 function again.
        // SHOULD FAIL
        vm.expectRevert(IModule.Module__CannotCallInit2Again.selector);
        paymentProcessor.init2(_proposal, dependencydata);
    }

    //--------------------------------------------------------------------------
    // Test: Payment Processing

    function testProcessPayments(address recipient, uint amount) public {
        vm.assume(recipient != address(paymentProcessor));
        vm.assume(recipient != address(ERC20PaymentClient));
        vm.assume(recipient != address(0));
        vm.assume(amount != 0);

        // Add payment order to client.
        ERC20PaymentClient.addPaymentOrder(
            IERC20PaymentClient.PaymentOrder({
                recipient: recipient,
                amount: amount,
                createdAt: block.timestamp,
                dueTo: block.timestamp
            })
        );

        // Call processPayments.
        vm.prank(address(ERC20PaymentClient));
        paymentProcessor.processPayments(ERC20PaymentClient);

        // Check correct balances.
        assertEq(_token.balanceOf(address(recipient)), amount);
        assertEq(_token.balanceOf(address(ERC20PaymentClient)), 0);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);
    }

    function testProcessPaymentsFailsWhenCalledByNonModule(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(ERC20PaymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__OnlyCallableByModule
                    .selector
            )
        );
        paymentProcessor.processPayments(ERC20PaymentClient);
    }

    function testProcessPaymentsFailsWhenCalledOnOtherClient(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(ERC20PaymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        ERC20PaymentClientMock otherERC20PaymentClient = new ERC20PaymentClientMock(_token);

        vm.prank(address(ERC20PaymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.processPayments(otherERC20PaymentClient);
    }

    function testCancelPaymentsFailsWhenCalledByNonModule(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(ERC20PaymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        vm.prank(nonModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__OnlyCallableByModule
                    .selector
            )
        );
        paymentProcessor.cancelRunningPayments(ERC20PaymentClient);
    }

    function testCancelPaymentsFailsWhenCalledOnOtherClient(address nonModule)
        public
    {
        vm.assume(nonModule != address(paymentProcessor));
        vm.assume(nonModule != address(ERC20PaymentClient));
        vm.assume(nonModule != address(_authorizer));
        // PaymentProcessorMock gets deployed and initialized in ModuleTest,
        // if deployed address is same as nonModule, this test will fail.
        vm.assume(nonModule != address(_paymentProcessor));
        vm.assume(nonModule != address(_fundingManager));

        ERC20PaymentClientMock otherERC20PaymentClient = new ERC20PaymentClientMock(_token);

        vm.prank(address(ERC20PaymentClient));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentProcessor
                    .Module__PaymentManager__CannotCallOnOtherClientsOrders
                    .selector
            )
        );
        paymentProcessor.cancelRunningPayments(otherERC20PaymentClient);
    }
}
