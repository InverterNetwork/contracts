// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {IERC20Errors} from "@oz/interfaces/draft-IERC6093.sol";

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
    bytes32 internal constant _START_END_CLIFF_FLAG =
        0x0000000000000000000000000000000000000000000000000000000000000007;

    // SuT
    ERC20PaymentClientBaseV1AccessMock paymentClient;
    FundingManagerV1Mock fundingManager;

    // Mocks
    ERC20Mock token;

    //--------------------------------------------------------------------------
    // Events

    event PaymentOrderAdded(
        address indexed recipient,
        address indexed token,
        uint amount,
        uint originChainId,
        uint targetChainId,
        bytes32 flags,
        bytes32[] data
    );

    function setUp() public {
        address impl = address(new ERC20PaymentClientBaseV1AccessMock());
        paymentClient = ERC20PaymentClientBaseV1AccessMock(Clones.clone(impl));

        _setUpOrchestrator(paymentClient);

        _authorizer.setIsAuthorized(address(this), true);

        paymentClient.init(_orchestrator, _METADATA, bytes(""));

        token = ERC20Mock(address(_orchestrator.fundingManager().token()));
    }

    // These are just placeholders, as the real PaymentProcessor is an abstract contract and not a real module
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
    // Test: exposed_addPaymentOrder()

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
            IERC20PaymentClientBase_v1.PaymentOrder memory order =
                _createPaymentOrder(address(_token), recipient, amount, end);

            vm.expectEmit();
            emit PaymentOrderAdded(
                recipient,
                address(_token),
                amount,
                block.chainid,
                block.chainid,
                _START_END_CLIFF_FLAG,
                order.data
            );

            paymentClient.exposed_addPaymentOrder(order);
        }

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        assertEq(orders.length, orderAmount);

        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);

            if (end != 0) {
                assertEq(orders[i].data[2], bytes32(end));
            }
        }

        assertEq(
            paymentClient.outstandingTokenAmount(address(_token)),
            amount * orderAmount
        );
    }

    function testAddPaymentOrderFailsForInvalidPaymentOrder() public {
        // Set return Value of validPaymentOrder in the paymentProcessor to false
        _paymentProcessor.flipValidOrder();

        vm.expectRevert(
            IERC20PaymentClientBase_v1
                .Module__ERC20PaymentClientBase__InvalidPaymentOrder
                .selector
        );
        paymentClient.exposed_addPaymentOrder(
            IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: address(0),
                paymentToken: address(_token),
                amount: 1,
                originChainId: block.chainid,
                targetChainId: block.chainid,
                flags: bytes32(0),
                data: new bytes32[](0)
            })
        );
    }

    //----------------------------------
    // Test: addPaymentOrders()

    function testAddPaymentOrders() public {
        IERC20PaymentClientBase_v1.PaymentOrder[] memory ordersToAdd =
            new IERC20PaymentClientBase_v1.PaymentOrder[](3);

        ordersToAdd[0] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0xCAFE1),
            paymentToken: address(_token),
            amount: 100e18,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: bytes32(0),
            data: new bytes32[](0)
        });

        uint flags = 0; // Initialize flags as uint128 to accumulate the bits
        flags |= (1 << 0); // Set bit 0 for start
        flags |= (1 << 1); // Set bit 1 for end
        bytes32 flagsBytes = bytes32(flags);
        bytes32[] memory data = new bytes32[](2);
        data[0] = bytes32(block.timestamp);
        data[1] = bytes32(block.timestamp + 1);

        ordersToAdd[1] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0xCAFE2),
            paymentToken: address(_token),
            amount: 100e18,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flagsBytes,
            data: data
        });

        bytes32[] memory data2 = new bytes32[](1);
        data[0] = bytes32(block.timestamp);
        data[1] = bytes32(block.timestamp + 2);

        ordersToAdd[2] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: address(0xCAFE3),
            paymentToken: address(_token),
            amount: 100e18,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flagsBytes,
            data: data2
        });

        vm.expectEmit();
        emit PaymentOrderAdded(
            address(0xCAFE1),
            address(_token),
            100e18,
            block.chainid,
            block.chainid,
            bytes32(0),
            new bytes32[](0)
        );
        emit PaymentOrderAdded(
            address(0xCAFE2),
            address(_token),
            100e18,
            block.chainid,
            block.chainid,
            bytes32(0),
            new bytes32[](0)
        );
        emit PaymentOrderAdded(
            address(0xCAFE3),
            address(_token),
            100e18,
            block.chainid,
            block.chainid,
            bytes32(0),
            new bytes32[](0)
        );
        paymentClient.exposed_addPaymentOrders(ordersToAdd);

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();
        assertEq(orders.length, 3);
        for (uint i; i < 3; ++i) {
            assertEq(orders[i].recipient, ordersToAdd[i].recipient);
            assertEq(orders[i].amount, ordersToAdd[i].amount);
            for (uint j; j < orders[i].data.length; ++j) {
                assertEq(orders[i].data[j], ordersToAdd[i].data[j]);
            }
        }
        assertEq(paymentClient.outstandingTokenAmount(address(_token)), 300e18);
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
        orderAmount = bound(orderAmount, 1, 100);
        amount = bound(amount, 1, 1_000_000_000_000_000_000);

        _assumeValidRecipient(recipient);

        // prep paymentClient
        _token.mint(address(_fundingManager), orderAmount * amount);

        for (uint i; i < orderAmount; ++i) {
            paymentClient.exposed_addPaymentOrder(
                _createPaymentOrder(address(_token), recipient, amount, end)
            );
        }

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        address[] memory tokens;
        uint[] memory totalOutstandingAmounts;
        vm.prank(address(_paymentProcessor));
        (orders, tokens, totalOutstandingAmounts) =
            paymentClient.collectPaymentOrders();

        // Check that orders are correct.
        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            if (end != 0) {
                assertEq(orders[i].data[2], bytes32(end));
            }
        }

        // Check that the returned token list and outstanding amounts are correct.
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(_token));
        assertEq(totalOutstandingAmounts.length, 1);
        assertEq(totalOutstandingAmounts[0], orderAmount * amount);

        // Check that orders in ERC20PaymentClientBase_v1 got reset.
        IERC20PaymentClientBase_v1.PaymentOrder[] memory updatedOrders;
        updatedOrders = paymentClient.paymentOrders();
        assertEq(updatedOrders.length, 0);

        // Check that outstanding token amount is still the same afterwards.
        assertEq(
            paymentClient.outstandingTokenAmount(address(_token)),
            totalOutstandingAmounts[0]
        );

        // Check that we received allowance to fetch tokens from ERC20PaymentClientBase_v1.
        assertTrue(
            _token.allowance(address(paymentClient), address(_paymentProcessor))
                >= totalOutstandingAmounts[0]
        );
    }

    function testCollectPaymentOrders_IfThereAreNoOrders() public {
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        address[] memory tokens;
        uint[] memory totalOutstandingAmounts;
        vm.prank(address(_paymentProcessor));
        (orders, tokens, totalOutstandingAmounts) =
            paymentClient.collectPaymentOrders();

        // Check that received values are correct.
        assertEq(orders.length, 0);
        assertEq(tokens.length, 0);
        assertEq(totalOutstandingAmounts.length, 0);

        // Check that there are no orders in the paymentClient
        IERC20PaymentClientBase_v1.PaymentOrder[] memory updatedOrders;
        updatedOrders = paymentClient.paymentOrders();
        assertEq(updatedOrders.length, 0);
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

        paymentClient.exposed_outstandingTokenAmount(address(token), preAmount);

        vm.prank(address(_paymentProcessor));
        paymentClient.amountPaid(address(token), amount);

        assertEq(
            preAmount - amount,
            paymentClient.outstandingTokenAmount(address(token))
        );
    }

    function testAmountPaidModifierInPosition(address caller) public {
        address fundingManagerToken =
            address(_orchestrator.fundingManager().token());
        paymentClient.exposed_outstandingTokenAmount(fundingManagerToken, 1);

        if (caller != address(_paymentProcessor)) {
            vm.expectRevert(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__CallerNotAuthorized
                    .selector
            );
        }

        vm.prank(address(caller));
        paymentClient.amountPaid(fundingManagerToken, 1);
    }

    //--------------------------------------------------------------------------
    // Test internal functions

    function testEnsureTokenBalance(uint amountRequired, uint currentFunds)
        public
    {
        amountRequired = bound(amountRequired, 1, 1_000_000_000_000e18);
        // prep paymentClient
        _token.mint(address(paymentClient), currentFunds);

        // create paymentOrder with required amount
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        _createPaymentOrder(
            address(_token), address(0xA11CE), amountRequired, block.timestamp
        );

        paymentClient.exposed_addPaymentOrder(order);

        _orchestrator.setInterceptData(true);

        if (currentFunds > amountRequired) {
            paymentClient.exposed_ensureTokenBalance(address(_token));
        } else if (
            _token.balanceOf(address(_fundingManager))
                < order.amount - _token.balanceOf(address(paymentClient))
        ) {
            // Check that Error works correctly
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    _fundingManager,
                    _token.balanceOf(address(_fundingManager)),
                    order.amount - _token.balanceOf(address(paymentClient))
                )
            );
            paymentClient.exposed_ensureTokenBalance(address(_token));
        }
    }

    function testEnsureTokenAllowance(uint firstAmount, uint secondAmount)
        public
    {
        // Set up reasonable boundaries
        firstAmount = bound(firstAmount, 1, type(uint).max / 2);
        secondAmount = bound(secondAmount, 1, type(uint).max / 2);

        // We make sure the allowance starts at zero
        assertEq(
            _token.allowance(address(paymentClient), address(_paymentProcessor)),
            0
        );

        // we add the first paymentOrder to increase the outstanding amount
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        _createPaymentOrder(
            address(_token), address(0xA11CE), firstAmount, block.timestamp
        );
        paymentClient.exposed_addPaymentOrder(order);

        // test ensureTokenAllowance
        paymentClient.exposed_ensureTokenAllowance(
            _paymentProcessor, address(_token)
        );

        uint currentAllowance =
            _token.allowance(address(paymentClient), address(_paymentProcessor));

        assertEq(currentAllowance, firstAmount);

        // we add a second paymentOrder to increase the outstanding amount
        order = _createPaymentOrder(
            address(_token), address(0xA11CE), secondAmount, block.timestamp
        );
        paymentClient.exposed_addPaymentOrder(order);

        // test ensureTokenAllowance now accounts for both
        paymentClient.exposed_ensureTokenAllowance(
            _paymentProcessor, address(_token)
        );

        currentAllowance =
            _token.allowance(address(paymentClient), address(_paymentProcessor));

        assertEq(currentAllowance, firstAmount + secondAmount);
    }

    function testIsAuthorizedPaymentProcessor(address addr) public {
        bool isAuthorized = paymentClient.exposed_isAuthorizedPaymentProcessor(
            IPaymentProcessor_v1(addr)
        );

        if (addr == address(_paymentProcessor)) {
            assertTrue(isAuthorized);
        } else {
            assertFalse(isAuthorized);
        }
    }

    function test_setFlags(uint8 flagCount_) public {
        bytes32 newFlags = 0;
        uint8[] memory flags = new uint8[](flagCount_);

        for (uint i = 0; i < flagCount_; i++) {
            newFlags |= bytes32((1 << i));
            flags[i] = uint8(i);
        }

        paymentClient.exposed_setFlags(flagCount_, flags);

        assertEq(paymentClient.getFlagCount(), flagCount_);
        assertEq(
            abi.encodePacked(paymentClient.getFlags()),
            abi.encodePacked(newFlags)
        );
    }

    function test_assemblePaymentConfig_FailsIfAmountOfFlagsIsIncorrect(
        bytes32[] memory flagValues
    ) public {
        vm.assume(flagValues.length != paymentClient.getFlagCount());

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20PaymentClientBase_v1
                    .Module__ERC20PaymentClientBase__MismatchBetweenFlagCountAndArrayLength
                    .selector,
                paymentClient.getFlagCount(),
                flagValues.length
            )
        );

        paymentClient.exposed_assemblePaymentConfig(flagValues);
    }

    function test_assemblePaymentConfig(bytes32[] memory randValues) public {
        uint8 flagCount = paymentClient.getFlagCount();
        bytes32[] memory flagValues = new bytes32[](flagCount);
        for (uint8 i; i < flagCount; ++i) {
            flagValues[i] = randValues[randValues.length % i];
        }

        (bytes32 ret_flags, bytes32[] memory ret_FlagValues) =
            paymentClient.exposed_assemblePaymentConfig(flagValues);

        assertEq(flagCount, ret_FlagValues.length);
        assertEq(ret_flags, paymentClient.getFlags());
        for (uint8 i; i < ret_FlagValues.length; ++i) {
            assertEq(ret_FlagValues[i], flagValues[i]);
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

    /// @dev    Returns all invalid recipients.
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

    /// @dev    Returns all invalid amounts.
    function _createInvalidAmounts() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint[](2);

        invalids[0] = 0;
        invalids[1] = type(uint).max / 100_000;

        return invalids;
    }

    /// @dev    Creates a PaymentOrder with the given parameters.
    function _createPaymentOrder(
        address paymentToken,
        address recipient,
        uint amount,
        uint end
    ) internal view returns (IERC20PaymentClientBase_v1.PaymentOrder memory) {
        bytes32[] memory data = new bytes32[](end != 0 ? 3 : 2);
        data[0] = bytes32(block.timestamp);
        data[1] = bytes32(0);
        if (end != 0) {
            data[2] = bytes32(end);
        }

        return IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            paymentToken: paymentToken,
            amount: amount,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: _START_END_CLIFF_FLAG,
            data: data
        });
    }
}
