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

import {PP_Simple_v1AccessMock} from
    "test/utils/mocks/modules/paymentProcessor/PP_Simple_v1AccessMock.sol";

import {
    PP_Simple_v1,
    IPaymentProcessor_v1
} from "src/modules/paymentProcessor/PP_Simple_v1.sol";

// Mocks
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_SimpleV1Test is ModuleTest {
    // SuT
    PP_Simple_v1AccessMock paymentProcessor;

    // Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;

    //--------------------------------------------------------------------------
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

    function setUp() public {
        address impl = address(new PP_Simple_v1AccessMock());
        paymentProcessor = PP_Simple_v1AccessMock(Clones.clone(impl));

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
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
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
        paymentClient.exposed_addPaymentOrder(
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipient,
                paymentToken: address(_token),
                amount: amount,
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: bytes32(0),
                data: new bytes32[](0)
            })
        );

        // emit UnclaimableAmountAdded(paymentClient: 0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758, recipient: 0x0000000000000000000000000000000000002aac, amount: 3523273495 [3.523e9])
        // emit UnclaimableAmountAdded(paymentClient: 0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758, token: ERC20Mock: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], recipient: 0x0000000000000000000000000000000000002aac, amount: 3523273495 [3.523e9])

        if (paymentsFail) {
            // transfers will fail by returning false now
            _token.toggleReturnFalse();
        }

        vm.expectEmit(true, true, true, true);
        emit IPaymentProcessor_v1.PaymentOrderProcessed(
            address(paymentClient),
            recipient,
            address(_token),
            amount,
            block.chainid,
            block.chainid,
            bytes32(0),
            new bytes32[](0)
        );
        if (!paymentsFail) {
            vm.expectEmit(true, true, true, true);
            emit TokensReleased(recipient, address(_token), amount);
        } else {
            vm.expectEmit(true, true, true, true);
            emit UnclaimableAmountAdded(
                address(paymentClient), address(_token), recipient, amount
            );
        }

        // Call processPayments.
        vm.prank(address(paymentClient));
        paymentProcessor.processPayments(paymentClient);

        // Invariant: Payment processor does not hold funds.
        assertEq(_token.balanceOf(address(paymentProcessor)), 0);

        // If call doesnt fail
        if (!paymentsFail) {
            // Check correct balances.
            assertEq(_token.balanceOf(address(recipient)), amount);
            assertEq(_token.balanceOf(address(paymentClient)), 0);

            assertEq(amount, paymentClient.amountPaidCounter(address(_token)));
            assertEq(
                paymentProcessor.unclaimable(
                    address(paymentClient), address(_token), recipient
                ),
                0
            );
        } // If call fails
        else {
            assertEq(0, paymentClient.amountPaidCounter(address(_token)));
            assertEq(
                paymentProcessor.unclaimable(
                    address(paymentClient), address(_token), recipient
                ),
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
            // If recipient is invalid change it
            if (recipients[i] == address(0) || recipients[i].code.length != 0) {
                recipients[i] = address(0x1);
            }
        }

        // transfers will fail by returning false now
        _token.toggleReturnFalse();

        // Add payment order to client and call processPayments.

        for (uint i = 0; i < recipients.length; i++) {
            uint flags = 0; // Initialize flags as uint128 to accumulate the bits
            flags |= (1 << 1); // Set bit 0 for start
            flags |= (1 << 3); // Set bit 3 for end

            bytes32 flagsBytes = bytes32(flags);
            bytes32[] memory data = new bytes32[](2);
            data[0] = bytes32(block.timestamp);
            data[1] = bytes32(block.timestamp);

            paymentClient.exposed_addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipients[i],
                    paymentToken: address(_token),
                    amount: 1,
                    originChainId: block.chainid,
                    targetChainId: block.chainid,
                    flags: flagsBytes,
                    data: data
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

            // Check that recipients are not handled twice
            // In case that the random array did it multiple times
            if (recipientsHandled[recipient]) continue;
            recipientsHandled[recipient] = true;

            amount = paymentProcessor.unclaimable(
                address(paymentClient), address(_token), recipient
            );

            // Do call
            vm.expectEmit(true, true, true, true);
            emit TokensReleased(recipient, address(_token), amount);

            vm.prank(recipient);
            paymentProcessor.claimPreviouslyUnclaimable(
                address(paymentClient), address(_token), recipient
            );

            assertEq(
                paymentProcessor.unclaimable(
                    address(paymentClient), address(_token), recipient
                ),
                0
            );

            // Amount send
            assertEq(_token.balanceOf(recipient), amount);

            // Check that amountPaid is correct in PaymentClient
            amountPaid += amount;
            assertEq(
                paymentClient.amountPaidCounter(address(_token)), amountPaid
            );
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
            address(paymentClient), address(0), address(0x1)
        );
    }

    function test_ValidPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        address sender
    ) public {
        // The randomToken can't be the address of the Create2Deployer
        // as that one uses a fallback funciton to deploy contracts, it will
        // pass the test here
        vm.assume(
            order.paymentToken != 0x4e59b44847b379578588920cA78FbF26c0B4956C
        );

        vm.startPrank(sender);
        bool expectedValue = paymentProcessor.exposed_validPaymentReceiver(
            order.recipient
        ) && paymentProcessor.exposed_validPaymentToken(order.paymentToken)
            && paymentProcessor.exposed__validTotal(order.amount);
        assertEq(paymentProcessor.validPaymentOrder(order), expectedValue);

        vm.stopPrank();
    }

    function test__validPaymentReceiver(address addr, address sender) public {
        bool expectedValue = true;
        if (
            addr == address(0) || addr == sender
                || addr == address(paymentProcessor)
                || addr == address(_orchestrator)
                || addr == address(_orchestrator.fundingManager().token())
        ) {
            expectedValue = false;
        }

        vm.prank(sender);

        assertEq(
            paymentProcessor.exposed_validPaymentReceiver(addr), expectedValue
        );
    }

    function test__validTotal(uint _total) public {
        bool expectedValue = true;
        if (_total == 0) {
            expectedValue = false;
        }

        assertEq(paymentProcessor.exposed__validTotal(_total), expectedValue);
    }

    function test__validPaymentToken(address randomToken, address sender)
        public
    {
        // Non-contract addresses or protected addresses should be invalid
        vm.assume(randomToken != address(_token));

        // The randomToken can't be the address of the Create2Deployer
        // as that one uses a fallback funciton to deploy contracts, it will
        // pass the test here
        vm.assume(randomToken != 0x4e59b44847b379578588920cA78FbF26c0B4956C);

        vm.prank(sender);

        assertEq(paymentProcessor.exposed_validPaymentToken(randomToken), false);

        // ERC20 addresses are valid
        ERC20Mock actualToken = new ERC20Mock("Test", "TST");

        vm.prank(sender);
        assertEq(
            paymentProcessor.exposed_validPaymentToken(address(actualToken)),
            true
        );

        vm.prank(sender);
        assertEq(
            paymentProcessor.exposed_validPaymentToken(address(_token)), true
        );
    }
}
