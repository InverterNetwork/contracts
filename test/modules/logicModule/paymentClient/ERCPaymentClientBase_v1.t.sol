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
import {
    ERC20PaymentClientBaseV1AccessMock,
    IERC20PaymentClientBase_v1
} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1AccessMock.sol";
import {Module_v1, IModule_v1} from "src/modules/base/Module_v1.sol";

import {OrchestratorV1Mock} from
    "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";

import {
    PaymentProcessorV1Mock,
    IPaymentProcessor_v1
} from "test/utils/mocks/modules/PaymentProcessorV1Mock.sol";
import {
    IFundingManager_v1,
    FundingManagerV1Mock
} from "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ERC20PaymentClientBaseV1Test is ModuleTest {
    // SuT
    ERC20PaymentClientBaseV1AccessMock paymentClient;
    FundingManagerV1Mock fundingManager;

    // Mocks
    ERC20Mock token;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Added a payment order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    event PaymentOrderAdded(address indexed recipient, uint amount);

    function setUp() public {
        address impl = address(new ERC20PaymentClientBaseV1AccessMock());
        paymentClient = ERC20PaymentClientBaseV1AccessMock(Clones.clone(impl));

        _setUpOrchestrator(paymentClient);

        _authorizer.setIsAuthorized(address(this), true);

        paymentClient.init(_orchestrator, _METADATA, bytes(""));
    }

    //These are just placeholders, as the real PaymentProcessor is an abstract contract and not a real module
    function testInit() public override {}

    function testReinitFails() public override {}

    function testSupportsInterface() public {
        assertTrue(
            paymentClient.supportsInterface(
                type(IERC20PaymentClientBase_v1).interfaceId
            )
        );
    }

    //----------------------------------
    // Test: addPaymentOrder()

    function testAddPaymentOrder(
        uint orderAmount,
        address recipient,
        uint amount,
        uint end
    ) public {
        // Note to stay reasonable.
        orderAmount = bound(orderAmount, 0, 100);
        amount = bound(amount, 1, 1_000_000_000_000_000_000);

        _assumeValidRecipient(recipient);
        _assumeValidAmount(amount);

        for (uint i; i < orderAmount; ++i) {
            vm.expectEmit();
            emit PaymentOrderAdded(recipient, amount);

            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    start: block.timestamp,
                    end: end
                })
            );
        }

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            assertEq(orders[i].end, end);
        }

        assertEq(paymentClient.outstandingTokenAmount(), amount * orderAmount);
    }

    function testAddPaymentOrderFailsForInvalidRecipient() public {
        address[] memory invalids = _createInvalidRecipients();
        uint amount = 1e18;
        uint end = block.timestamp;

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__InvalidRecipient
                    .selector
            );
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: invalids[0],
                    amount: amount,
                    start: block.timestamp,
                    end: end
                })
            );
        }
    }

    function testAddPaymentOrderFailsForInvalidAmount() public {
        address recipient = address(0xCAFE);
        uint[] memory invalids = _createInvalidAmounts();
        uint end = block.timestamp;

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__InvalidAmount
                    .selector
            );
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: invalids[0],
                    start: block.timestamp,
                    end: end
                })
            );
        }
    }

    //----------------------------------
    // Test: addPaymentOrders()

    function testAddPaymentOrders() public {
        IERC20PaymentClientBase_v1.PaymentOrder[] memory ordersToAdd =
            new IERC20PaymentClientBase_v1.PaymentOrder[](3);
        ordersToAdd[0] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0xCAFE1),
            amount: 100e18,
            start: block.timestamp,
            end: block.timestamp
        });
        ordersToAdd[1] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0xCAFE2),
            amount: 100e18,
            start: block.timestamp,
            end: block.timestamp + 1
        });
        ordersToAdd[2] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0xCAFE3),
            amount: 100e18,
            start: block.timestamp,
            end: block.timestamp + 2
        });

        vm.expectEmit();
        emit PaymentOrderAdded(address(0xCAFE1), 100e18);
        emit PaymentOrderAdded(address(0xCAFE2), 100e18);
        emit PaymentOrderAdded(address(0xCAFE3), 100e18);

        paymentClient.addPaymentOrders(ordersToAdd);

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        assertEq(orders.length, 3);
        for (uint i; i < 3; ++i) {
            assertEq(orders[i].recipient, ordersToAdd[i].recipient);
            assertEq(orders[i].amount, ordersToAdd[i].amount);
            assertEq(orders[i].end, ordersToAdd[i].end);
        }

        assertEq(paymentClient.outstandingTokenAmount(), 300e18);
    }

    //----------------------------------
    // Test: collectPaymentOrders()

    function testCollectPaymentOrders(
        uint orderAmount,
        address recipient,
        uint amount,
        uint end
    ) public {
        // Note to stay reasonable.
        orderAmount = bound(orderAmount, 0, 100);
        amount = bound(amount, 1, 1_000_000_000_000_000_000);

        _assumeValidRecipient(recipient);

        //prep paymentClient
        _token.mint(address(_fundingManager), orderAmount * amount);

        for (uint i; i < orderAmount; ++i) {
            paymentClient.addPaymentOrder(
                IERC20PaymentClientBase_v1.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    start: block.timestamp,
                    end: end
                })
            );
        }

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        uint totalOutstandingAmount;
        vm.prank(address(_paymentProcessor));
        (orders, totalOutstandingAmount) = paymentClient.collectPaymentOrders();

        // Check that orders are correct.
        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            assertEq(orders[i].end, end);
        }

        // Check that total outstanding token amount is correct.
        assertEq(totalOutstandingAmount, orderAmount * amount);

        // Check that orders in ERC20PaymentClientBase_v1 got reset.
        IERC20PaymentClientBase_v1.PaymentOrder[] memory updatedOrders;
        updatedOrders = paymentClient.paymentOrders();
        assertEq(updatedOrders.length, 0);

        // Check that outstanding token amount is still the same afterwards.
        assertEq(paymentClient.outstandingTokenAmount(), totalOutstandingAmount);

        // Check that we received allowance to fetch tokens from ERC20PaymentClientBase_v1.
        assertTrue(
            _token.allowance(address(paymentClient), address(_paymentProcessor))
                >= totalOutstandingAmount
        );
    }

    function testCollectPaymentOrdersFailsCallerNotAuthorized() public {
        vm.expectRevert(
            IERC20PaymentClientBase_v1
                .Module__ERC20PaymentClientBase__CallerNotAuthorized
                .selector
        );
        paymentClient.collectPaymentOrders();
    }

    //----------------------------------
    // Test: amountPaid()

    function testAmountPaid(uint preAmount, uint amount) public {
        vm.assume(preAmount >= amount);
        paymentClient.set_outstandingTokenAmount(preAmount);

        vm.prank(address(_paymentProcessor));
        paymentClient.amountPaid(amount);

        assertEq(preAmount - amount, paymentClient.outstandingTokenAmount());
    }

    function testAmountPaidModifierInPosition(address caller) public {
        paymentClient.set_outstandingTokenAmount(1);

        if (caller != address(_paymentProcessor)) {
            vm.expectRevert(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__CallerNotAuthorized
                    .selector
            );
        }

        vm.prank(address(caller));
        paymentClient.amountPaid(1);
    }

    //--------------------------------------------------------------------------
    // Test internal functions

    function testEnsureTokenBalance(uint amountRequired, uint currentFunds)
        public
    {
        //prep paymentClient
        _token.mint(address(paymentClient), currentFunds);

        _orchestrator.setInterceptData(true);

        if (currentFunds >= amountRequired) {
            _orchestrator.setExecuteTxBoolReturn(true);
            //NoOp as we already have enough funds
            assertEq(bytes(""), _orchestrator.executeTxData());
        } else {
            //Check that Error works correctly
            vm.expectRevert(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__TokenTransferFailed
                    .selector
            );
            paymentClient.originalEnsureTokenBalance(amountRequired);

            _orchestrator.setExecuteTxBoolReturn(true);

            paymentClient.originalEnsureTokenBalance(amountRequired);

            //callback from orchestrator to transfer tokens has to be in this form
            assertEq(
                abi.encodeCall(
                    IFundingManager_v1.transferOrchestratorToken,
                    (address(paymentClient), amountRequired - currentFunds)
                ),
                _orchestrator.executeTxData()
            );
        }
    }

    function testEnsureTokenAllowance(uint initialAllowance, uint amount)
        public
    {
        //Set up reasonable boundaries
        initialAllowance = bound(initialAllowance, 0, type(uint).max / 2);
        amount = bound(amount, 0, type(uint).max / 2);

        //Set up initial allowance
        vm.prank(address(paymentClient));
        _token.approve(address(_paymentProcessor), initialAllowance);

        paymentClient.originalEnsureTokenAllowance(_paymentProcessor, amount);

        uint currentAllowance =
            _token.allowance(address(paymentClient), address(_paymentProcessor));

        assertEq(currentAllowance, initialAllowance + amount);
    }

    function testIsAuthorizedPaymentProcessor(address addr) public {
        bool isAuthorized = paymentClient.originalIsAuthorizedPaymentProcessor(
            IPaymentProcessor_v1(addr)
        );

        if (addr == address(_paymentProcessor)) {
            assertTrue(isAuthorized);
        } else {
            assertFalse(isAuthorized);
        }
    }

    //--------------------------------------------------------------------------
    // Assume Helper Functions

    function _assumeValidRecipient(address recipient) internal view {
        address[] memory invalids = _createInvalidRecipients();
        for (uint i; i < invalids.length; ++i) {
            vm.assume(recipient != invalids[i]);
        }
    }

    function _assumeValidAmount(uint amount) internal pure {
        uint[] memory invalids = _createInvalidAmounts();
        for (uint i; i < invalids.length; ++i) {
            vm.assume(amount != invalids[i]);
        }
    }

    //--------------------------------------------------------------------------
    // Data Creation Helper Functions

    /// @dev Returns all invalid recipients.
    function _createInvalidRecipients()
        internal
        view
        returns (address[] memory)
    {
        address[] memory invalids = new address[](5);

        invalids[0] = address(0);
        invalids[1] = address(paymentClient);
        invalids[2] = address(_fundingManager);
        invalids[3] = address(_paymentProcessor);
        invalids[4] = address(_orchestrator);

        return invalids;
    }

    /// @dev Returns all invalid amounts.
    function _createInvalidAmounts() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint[](2);

        invalids[0] = 0;
        invalids[1] = type(uint).max / 100_000;

        return invalids;
    }
}
