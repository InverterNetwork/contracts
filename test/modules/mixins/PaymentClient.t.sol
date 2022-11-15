// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// SuT
import {
    PaymentClientMock,
    IPaymentClient
} from "test/utils/mocks/modules/mixins/PaymentClientMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract PaymentClientTest is Test {
    // SuT
    PaymentClientMock paymentClient;

    // Mocks
    ERC20Mock token;

    function setUp() public {
        token = new ERC20Mock("Mock", "MOCK");

        paymentClient = new PaymentClientMock(token);
        paymentClient.setIsAuthorized(address(this), true);
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
        vm.assume(orderAmount < 10);

        _assumeValidRecipient(recipient);
        _assumeValidAmount(amount);
        _assumeValidDueTo(dueTo);

        // Sum of all token amounts should not overflow.
        uint sum;
        for (uint i; i < orderAmount; i++) {
            unchecked {
                sum += amount;
            }
            vm.assume(sum > amount);
        }

        for (uint i; i < orderAmount; i++) {
            paymentClient.addPaymentOrder(recipient, amount, dueTo);
        }

        IPaymentClient.PaymentOrder[] memory orders =
            paymentClient.paymentOrders();

        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; i++) {
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

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IPaymentClient.Module__PaymentClient__InvalidRecipient.selector
            );
            paymentClient.addPaymentOrder(invalids[0], amount, dueTo);
        }
    }

    function testAddPaymentOrderFailsForInvalidAmount() public {
        address recipient = address(0xCAFE);
        uint[] memory invalids = _createInvalidAmounts();
        uint dueTo = block.timestamp;

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IPaymentClient.Module__PaymentClient__InvalidAmount.selector
            );
            paymentClient.addPaymentOrder(recipient, invalids[0], dueTo);
        }
    }

    function testAddPaymentOrderFailsForInvalidDueTo() public {
        address recipient = address(0xCAFE);
        uint amount = 1e18;
        uint[] memory invalids = _createInvalidDueTos();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IPaymentClient.Module__PaymentClient__InvalidDueTo.selector
            );
            paymentClient.addPaymentOrder(recipient, amount, invalids[0]);
        }
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
        vm.assume(orderAmount < 10);

        _assumeValidRecipient(recipient);
        _assumeValidAmount(amount);
        _assumeValidDueTo(dueTo);

        // Sum of all token amounts should not overflow.
        uint sum;
        for (uint i; i < orderAmount; i++) {
            unchecked {
                sum += amount;
            }
            vm.assume(sum > amount);
        }

        for (uint i; i < orderAmount; i++) {
            paymentClient.addPaymentOrder(recipient, amount, dueTo);
        }

        IPaymentClient.PaymentOrder[] memory orders;
        uint totalOutstandingAmount;
        (orders, totalOutstandingAmount) = paymentClient.collectPaymentOrders();

        // Check that orders are correct.
        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; i++) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            assertEq(orders[i].dueTo, dueTo);
        }

        // Check that total outstanding token amount is correct.
        assertEq(totalOutstandingAmount, orderAmount * amount);

        // Check that orders in PaymentClient got reset.
        IPaymentClient.PaymentOrder[] memory updatedOrders;
        updatedOrders = paymentClient.paymentOrders();
        assertEq(updatedOrders.length, 0);

        // Check that outstanding token amount in PaymentClient got reset.
        assertEq(paymentClient.outstandingTokenAmount(), 0);

        // Check that we received allowance to fetch tokens from PaymentClient.
        assertTrue(
            token.allowance(address(paymentClient), address(this))
                >= totalOutstandingAmount
        );
    }

    function testCollectPaymentOrdersFailsCallerNotAuthorized() public {
        paymentClient.setIsAuthorized(address(this), false);

        vm.expectRevert(
            IPaymentClient.Module__PaymentClient__CallerNotAuthorized.selector
        );
        paymentClient.collectPaymentOrders();
    }

    //--------------------------------------------------------------------------
    // Assume Helper Functions

    function _assumeValidRecipient(address recipient) internal {
        address[] memory invalids = _createInvalidRecipients();
        for (uint i; i < invalids.length; i++) {
            vm.assume(recipient != invalids[i]);
        }
    }

    function _assumeValidAmount(uint amount) internal {
        uint[] memory invalids = _createInvalidAmounts();
        for (uint i; i < invalids.length; i++) {
            vm.assume(amount != invalids[i]);
        }
    }

    function _assumeValidDueTo(uint dueTo) internal {
        uint[] memory invalids = _createInvalidDueTos();
        for (uint i; i < invalids.length; i++) {
            vm.assume(dueTo != invalids[i]);
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

    /// @dev Returns possible invalid dueTos.
    function _createInvalidDueTos() internal view returns (uint[] memory) {
        uint[] memory invalids = new uint[](1);

        invalids[0] = block.timestamp - 1;

        return invalids;
    }
}
