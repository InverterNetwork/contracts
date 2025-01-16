// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// Internal Dependencies
import {Module_v1, ContextUpgradeable} from "src/modules/base/Module_v1.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter ERC20 Payment Client Base
 *
 * @notice  Enables modules within the Inverter Network to create and manage payment orders
 *          that can be processed by authorized payment processors, ensuring efficient
 *          and secure transactions.
 *
 * @dev     Utilizes {SafeERC20} for token operations and integrates with {IPaymentProcessor_v1}
 *          to handle token payments. This abstract contract must be extended by modules
 *          that manage {ERC20} payment orders, supporting complex payment scenarios.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
abstract contract ERC20PaymentClientBase_v1 is
    IERC20PaymentClientBase_v1,
    Module_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IERC20PaymentClientBase_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;
    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev	Modifier to guarantee the recipient is valid.
    modifier validRecipient(address recipient) {
        _ensureValidRecipient(recipient);
        _;
    }

    /// @dev	Modifier to guarantee the amount is valid.
    modifier validAmount(uint amount) {
        _ensureValidAmount(amount);
        _;
    }

    /// @dev	Modifier to guarantee the payment order is valid.
    modifier validPaymentOrder(PaymentOrder memory order) {
        _ensureValidPaymentOrder(order);
        _;
    }

    //--------------------------------------------------------------------------
    // State

    /// @dev	The list of oustanding orders.
    /// @dev	Emptied whenever orders are collected.
    PaymentOrder[] internal _orders;

    /// @dev	The current cumulative amount of tokens outstanding.
    mapping(address => uint) internal _outstandingTokenAmounts;

    /// @dev    The number of payment processor flags used by this payment
    ///         client.
    uint8 internal _flagCount;

    /// @dev    The payment processor flags used by this payment client.
    bytes32 internal _flags;

    /// @dev	Storage gap for future upgrades.
    uint[48] private __gap;

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    /// @dev	Initializes the staking contract.
    /// @param  flags_ The flags, represented as an array of uint8 containing
    ///         the flag IDs between 0 and 255.
    function __ERC20PaymentClientBase_v1_init(uint8[] memory flags_)
        internal
        onlyInitializing
    {
        uint amountOfFlags = flags_.length;
        if (amountOfFlags > type(uint8).max) {
            revert Module__ERC20PaymentClientBase_v1__FlagAmountTooHigh();
        }
        _setFlags(uint8(flags_.length), flags_);
    }

    /// @dev	Adds a new {PaymentOrder} to the list of outstanding orders.
    /// @param  order The new payment order.
    function _addPaymentOrder(PaymentOrder memory order)
        internal
        virtual
        validPaymentOrder(order)
    {
        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmounts[order.paymentToken] += order.amount;

        // Add new order to list of oustanding orders.
        _orders.push(order);

        emit PaymentOrderAdded(
            order.recipient,
            order.paymentToken,
            order.amount,
            order.originChainId,
            order.targetChainId,
            order.flags,
            order.data
        );
    }

    /// @dev	Adds a set of new {PaymentOrder}s to the list of outstanding
    ///         orders.
    /// @param  orders The list of new Payment Orders.
    function _addPaymentOrders(PaymentOrder[] memory orders) internal virtual {
        uint orderAmount = orders.length;

        for (uint i; i < orderAmount; ++i) {
            _addPaymentOrder(orders[i]);
        }
    }

    /// @dev    Sets the flags for the PaymentOrders.
    /// @param  flagCount_ The number of flags.
    /// @param  flags_ The flags, represented as an array of uint8 containing
    ///         the flag IDs between 0 and 255.
    function _setFlags(uint8 flagCount_, uint8[] memory flags_)
        internal
        virtual
    {
        if (flagCount_ != flags_.length) {
            revert
                Module__ERC20PaymentClientBase__MismatchBetweenFlagCountAndArrayLength(
                flagCount_, flags_.length
            );
        }

        _flagCount = flagCount_;

        _flags = 0;
        for (uint8 i = 0; i < flagCount_; i++) {
            _flags |= bytes32((1 << flags_[i]));
        }

        emit FlagsSet(flagCount_, _flags);
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClientBase_v1 Functions

    /// @inheritdoc IERC20PaymentClientBase_v1
    function paymentOrders()
        external
        view
        virtual
        returns (PaymentOrder[] memory)
    {
        return _orders;
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function outstandingTokenAmount(address token_)
        external
        view
        virtual
        returns (uint total_)
    {
        return _outstandingTokenAmounts[token_];
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function collectPaymentOrders()
        external
        virtual
        returns (
            PaymentOrder[] memory paymentOrders_,
            address[] memory tokens_,
            uint[] memory totalAmounts_
        )
    {
        // Ensure caller is authorized to act as payment processor.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor_v1(_msgSender())))
        {
            revert Module__ERC20PaymentClientBase__CallerNotAuthorized();
        }

        // Create a copy of all orders to return.
        uint ordersLength = _orders.length;
        uint tokenCount;

        address[] memory tokens_buffer = new address[](ordersLength);
        uint[] memory amounts_buffer = new uint[](ordersLength);
        paymentOrders_ = new PaymentOrder[](ordersLength);

        for (uint i; i < ordersLength; ++i) {
            paymentOrders_[i] = _orders[i];
            bool found;
            for (uint j; j < tokenCount; ++j) {
                if (tokens_buffer[j] == paymentOrders_[i].paymentToken) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                // if the token is not in the list, add it
                tokens_buffer[tokenCount] = paymentOrders_[i].paymentToken;
                amounts_buffer[tokenCount] =
                    _outstandingTokenAmounts[paymentOrders_[i].paymentToken];
                tokenCount++;
            }
        }

        // Delete all outstanding orders.
        delete _orders;

        // Prepare the arrays that will be sent back
        tokens_ = new address[](tokenCount);
        totalAmounts_ = new uint[](tokenCount);

        for (uint i; i < tokenCount; ++i) {
            tokens_[i] = tokens_buffer[i];
            totalAmounts_[i] = amounts_buffer[i];

            // Ensure payment processor is able to fetch the tokens from address(this).
            _ensureTokenAllowance(
                IPaymentProcessor_v1(_msgSender()), tokens_[i]
            );

            // Ensure that the Client will have sufficient funds.
            // Note that while we also control when adding a payment order, more complex payment systems with
            // f.ex. deferred payments may not guarantee that having enough balance available when adding the order
            // means it'll have enough balance when the order is processed.
            _ensureTokenBalance(tokens_[i]);
        }

        // Return copy of orders and orders' total token amount to payment
        // processor.
        return (paymentOrders_, tokens_, totalAmounts_);
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function amountPaid(address token_, uint amount_) external virtual {
        // Ensure caller is authorized to act as payment processor.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor_v1(_msgSender())))
        {
            revert Module__ERC20PaymentClientBase__CallerNotAuthorized();
        }

        // reduce outstanding token amount by the given amount
        _outstandingTokenAmounts[token_] -= amount_;
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function getFlags() public view returns (bytes32 flags_) {
        return (_flags);
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function getFlagCount() public view returns (uint8 flagCount_) {
        return _flagCount;
    }

    //--------------------------------------------------------------------------
    // Private Functions

    /// @dev	Ensures the recipient is valid.
    /// @param  recipient The recipient to check.
    function _ensureValidRecipient(address recipient) private view {
        if (recipient == address(0) || recipient == address(this)) {
            revert Module__ERC20PaymentClientBase__InvalidRecipient();
        }
    }

    /// @dev	Ensures the amount is valid.
    /// @param  amount The amount to check.
    function _ensureValidAmount(uint amount) private pure {
        if (amount == 0) {
            revert Module__ERC20PaymentClientBase__InvalidAmount();
        }
    }

    /// @dev	Ensures the token is valid.
    /// @param  token The token to check.
    function _ensureValidToken(address token) private pure {
        if (token == address(0)) {
            revert Module__ERC20PaymentClientBase__InvalidToken();
        }
    }

    /// @dev	Ensures the payment order is valid.
    /// @param  order The payment order to check.
    function _ensureValidPaymentOrder(PaymentOrder memory order) private {
        if (!(orchestrator().paymentProcessor().validPaymentOrder(order))) {
            revert Module__ERC20PaymentClientBase__InvalidPaymentOrder();
        }
    }

    //--------------------------------------------------------------------------
    // {ERC20PaymentClientBase_v1} Function Implementations

    /// @dev	Ensures `amount` of payment tokens exist in address(this). In case the token being paid out is the
    ///         FundingManager token, it will trigger a callback to the FundingManager to transfer the tokens to
    function _ensureTokenBalance(address token) internal virtual {
        uint amount = _outstandingTokenAmounts[token];
        uint currentFunds = IERC20(token).balanceOf(address(this));

        // If current funds are not enough
        if (currentFunds < amount) {
            // check if the token is the FudningManager token and transfer it
            if (
                token == address(__Module_orchestrator.fundingManager().token())
            ) {
                // Get FundingManager address from orchestrator to transfer tokens
                // to address(this). Fails on ERC20 level if insufficient balance

                __Module_orchestrator.fundingManager().transferOrchestratorToken(
                    address(this), (amount - currentFunds)
                );
            } else {
                revert Module__ERC20PaymentClientBase__InsufficientFunds(token);
            }
        }
    }

    /// @dev	Ensures `amount` of token allowance for payment processor(s).
    function _ensureTokenAllowance(IPaymentProcessor_v1 spender, address token)
        internal
        virtual
    {
        IERC20(token).forceApprove(
            address(spender), _outstandingTokenAmounts[token]
        );
    }

    /// @dev	Returns whether address `who` is an authorized payment processor.
    function _isAuthorizedPaymentProcessor(IPaymentProcessor_v1 who)
        internal
        view
        virtual
        returns (bool)
    {
        return __Module_orchestrator.paymentProcessor() == who;
    }

    /// @dev	Returns the payment configuration from a list of supplied flag
    ///         values. Can be overriden to add additional validation steps.
    function _assemblePaymentConfig(bytes32[] memory flagValues_)
        internal
        view
        virtual
        returns (bytes32 flags_, bytes32[] memory data_)
    {
        if (_flagCount != flagValues_.length) {
            revert
                Module__ERC20PaymentClientBase__MismatchBetweenFlagCountAndArrayLength(
                _flagCount, flagValues_.length
            );
        }

        return (_flags, flagValues_);
    }
}
