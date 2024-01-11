// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// SuT
import {
    ERC20PaymentClientMock,
    IERC20PaymentClient
} from "test/utils/mocks/modules/ERC20PaymentClientMock.sol";
import {Module, IModule} from "src/modules/base/Module.sol";

import {OrchestratorMock} from
    "test/utils/mocks/orchestrator/OrchestratorMock.sol";

import {
    PaymentProcessorMock,
    IPaymentProcessor
} from "test/utils/mocks/modules/PaymentProcessorMock.sol";

import {
    IFundingManager,
    FundingManagerMock
} from "test/utils/mocks/modules/FundingManagerMock.sol";
// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ERC20PaymentClientTest is Test {
    // SuT
    ERC20PaymentClientMock paymentClient;
    OrchestratorMock orchestrator;
    PaymentProcessorMock paymentProcessor;
    FundingManagerMock fundingManager;

    // Mocks
    ERC20Mock token;

    function setUp() public {
        token = new ERC20Mock("Mock", "MOCK");

        paymentClient = new ERC20PaymentClientMock(token);
        paymentClient.setIsAuthorized(address(this), true);
    }

    function testSupportsInterface(bytes4 interfaceId) public {
        bool shouldBeInterface = type(IERC20PaymentClient).interfaceId
            == interfaceId || type(IModule).interfaceId == interfaceId
            || type(IERC165).interfaceId == interfaceId;

        assertEq(
            shouldBeInterface, paymentClient.supportsInterface(interfaceId)
        );
    }

    //----------------------------------
    // Test: addPaymentOrder()

    function testAddPaymentOrder(
        uint orderAmount,
        address recipient,
        uint amount,
        uint dueTo
    ) public {
        // Note to stay reasonable.
        orderAmount = bound(orderAmount, 0, 10);

        _assumeValidRecipient(recipient);
        _assumeValidAmount(amount);

        // Sum of all token amounts should not overflow.
        uint sum;
        for (uint i; i < orderAmount; ++i) {
            unchecked {
                sum += amount;
            }
            vm.assume(sum > amount);
        }

        for (uint i; i < orderAmount; ++i) {
            paymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }

        IERC20PaymentClient.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            assertEq(orders[i].dueTo, dueTo);
        }

        assertEq(paymentClient.outstandingTokenAmount(), amount * orderAmount);
    }

    function testAddPaymentOrderFailsForInvalidRecipient() public {
        address[] memory invalids = _createInvalidRecipients();
        uint amount = 1e18;
        uint dueTo = block.timestamp;

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IERC20PaymentClient
                    .Module__ERC20PaymentClient__InvalidRecipient
                    .selector
            );
            paymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: invalids[0],
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }
    }

    function testAddPaymentOrderFailsForInvalidAmount() public {
        address recipient = address(0xCAFE);
        uint[] memory invalids = _createInvalidAmounts();
        uint dueTo = block.timestamp;

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IERC20PaymentClient
                    .Module__ERC20PaymentClient__InvalidAmount
                    .selector
            );
            paymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: recipient,
                    amount: invalids[0],
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }
    }

    //----------------------------------
    // Test: addPaymentOrders()

    function testAddPaymentOrders() public {
        IERC20PaymentClient.PaymentOrder[] memory ordersToAdd =
            new IERC20PaymentClient.PaymentOrder[](3);
        ordersToAdd[0] = IERC20PaymentClient.PaymentOrder({
            recipient: address(0xCAFE1),
            amount: 100e18,
            createdAt: block.timestamp,
            dueTo: block.timestamp
        });
        ordersToAdd[1] = IERC20PaymentClient.PaymentOrder({
            recipient: address(0xCAFE2),
            amount: 100e18,
            createdAt: block.timestamp,
            dueTo: block.timestamp + 1
        });
        ordersToAdd[2] = IERC20PaymentClient.PaymentOrder({
            recipient: address(0xCAFE3),
            amount: 100e18,
            createdAt: block.timestamp,
            dueTo: block.timestamp + 2
        });

        paymentClient.addPaymentOrders(ordersToAdd);

        IERC20PaymentClient.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        assertEq(orders.length, 3);
        for (uint i; i < 3; ++i) {
            assertEq(orders[i].recipient, ordersToAdd[i].recipient);
            assertEq(orders[i].amount, ordersToAdd[i].amount);
            assertEq(orders[i].dueTo, ordersToAdd[i].dueTo);
        }

        assertEq(paymentClient.outstandingTokenAmount(), 300e18);
    }

    //----------------------------------
    // Test: collectPaymentOrders()

    function testCollectPaymentOrders(
        uint orderAmount,
        address recipient,
        uint amount,
        uint dueTo
    ) public {
        // Note to stay reasonable.
        orderAmount = bound(orderAmount, 0, 10);

        _assumeValidRecipient(recipient);
        _assumeValidAmount(amount);

        // Sum of all token amounts should not overflow.
        uint sum;
        for (uint i; i < orderAmount; ++i) {
            unchecked {
                sum += amount;
            }
            vm.assume(sum > amount);
        }

        for (uint i; i < orderAmount; ++i) {
            paymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }

        IERC20PaymentClient.PaymentOrder[] memory orders;
        uint totalOutstandingAmount;
        (orders, totalOutstandingAmount) = paymentClient.collectPaymentOrders();

        // Check that orders are correct.
        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            assertEq(orders[i].dueTo, dueTo);
        }

        // Check that total outstanding token amount is correct.
        assertEq(totalOutstandingAmount, orderAmount * amount);

        // Check that orders in ERC20PaymentClient got reset.
        IERC20PaymentClient.PaymentOrder[] memory updatedOrders;
        updatedOrders = paymentClient.paymentOrders();
        assertEq(updatedOrders.length, 0);

        // Check that outstanding token amount in ERC20PaymentClient got reset.
        assertEq(paymentClient.outstandingTokenAmount(), 0);

        // Check that we received allowance to fetch tokens from ERC20PaymentClient.
        assertTrue(
            token.allowance(address(paymentClient), address(this))
                >= totalOutstandingAmount
        );
    }

    function testCollectPaymentOrdersFailsCallerNotAuthorized() public {
        paymentClient.setIsAuthorized(address(this), false);

        vm.expectRevert(
            IERC20PaymentClient
                .Module__ERC20PaymentClient__CallerNotAuthorized
                .selector
        );
        paymentClient.collectPaymentOrders();
    }

    //--------------------------------------------------------------------------
    // Test internal functions

    function testEnsureTokenBalance(uint amountRequired) public {
        setupInternalFunctionTest();

        //Check that Error works correctly
        vm.expectRevert(
            IERC20PaymentClient
                .Module__ERC20PaymentClient__TokenTransferFailed
                .selector
        );
        paymentClient.originalEnsureTokenBalance(amountRequired);

        orchestrator.setExecuteTxBoolReturn(true);

        paymentClient.originalEnsureTokenBalance(amountRequired);

        assertEq(
            abi.encodeCall(
                IFundingManager.transferOrchestratorToken,
                (address(paymentClient), amountRequired)
            ),
            orchestrator.executeTxData()
        );
    }

    function testEnsureTokenAllowance(uint initialAllowance, uint postAllowance)
        public
    {
        setupInternalFunctionTest();

        //Set up initial allowance
        vm.prank(address(paymentClient));
        token.approve(address(paymentProcessor), initialAllowance);

        paymentClient.originalEnsureTokenAllowance(
            paymentProcessor, postAllowance
        );

        uint currentAllowance =
            token.allowance(address(paymentClient), address(paymentProcessor));

        if (initialAllowance > postAllowance) {
            assertEq(currentAllowance, initialAllowance);
        } else {
            assertEq(currentAllowance, postAllowance);
        }
    }

    function testIsAuthorizedPaymentProcessor(address addr) public {
        setupInternalFunctionTest();
        bool isAuthorized = paymentClient.originalIsAuthorizedPaymentProcessor(
            IPaymentProcessor(addr)
        );

        if (addr == address(paymentProcessor)) {
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

    function setupInternalFunctionTest() internal {
        paymentProcessor = new PaymentProcessorMock();
        fundingManager = new FundingManagerMock();
        orchestrator = new OrchestratorMock();
        orchestrator.setPaymentProcessor(paymentProcessor);
        orchestrator.setFundingManager(fundingManager);
        paymentClient.setOrchestrator(orchestrator);

        fundingManager.setToken(token);
        orchestrator.setToken(token);
    }

    //--------------------------------------------------------------------------
    // Data Creation Helper Functions

    /// @dev Returns all invalid recipients.
    function _createInvalidRecipients()
        internal
        view
        returns (address[] memory)
    {
        address[] memory invalids = new address[](2);

        invalids[0] = address(0);
        invalids[1] = address(paymentClient);

        return invalids;
    }

    /// @dev Returns all invalid amounts.
    function _createInvalidAmounts() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint[](1);

        invalids[0] = 0;

        return invalids;
    }
}
