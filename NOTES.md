# Payment Order Struct

## Relevant places in the code

### Where are new payments currently added?

- LM_PC_Bounties_v1
  - start = end = block.timestamp (cliff = 0)
- LM_PC_PaymentRouter_v1
  - currently if no start, sets block timestamp as start; leaves cliff & end up to user?
- LM_PC_RecurringPayments_v1
  - start = block.timestamp
  - cliff = 0
  - end = (currentEpoch + 1) \* epochLength (where epochLength is set in the module)
- LM_PC_Staking_v1
  - start = end = block.timestamp (cliff = 0)

### What happens when adding a payment?

```solidity
// ERC20PaymentClientBase_v1.sol

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
        order.recipient, order.paymentToken, order.amount
    );
}
```

- records the amount of outstanding payments PER TOKEN
- adds the PaymentOrder to an array of payment orders that is stored in state

### How are the orders processed?

#### Collect Payment Orders

- not actually collecting any orders
- returns three lists:
  - 1. list of payment orders (essentially raw `_orders` array)
  - 2. list of tokens
  - 3. list of amounts
- approves the token amounts to the payment processor
- checks if client holds enough tokens
- if it is the funding manager token, sends required amount of funding tokens from fm to client

```solidity
// ERC20PaymentClientBase_v1.sol

function collectPaymentOrders()
        external
        virtual
        returns (PaymentOrder[] memory, address[] memory, uint[] memory)
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
        PaymentOrder[] memory copy = new PaymentOrder[](ordersLength);

        // iterates over raw _orders
        for (uint i; i < ordersLength; ++i) {
            copy[i] = _orders[i];
            bool found;
            // iterates over tokens
            // if the token address exists already, do nothing, break out of loop
            // Note: this works because when adding a payment the total outstanding amount for a token is maintained
            // so that if the same token is twice in the list, it's not necessary to add amounts each time
            for (uint j; j < tokenCount; ++j) {
                if (tokens_buffer[j] == copy[i].paymentToken) {
                    found = true;
                    break;
                }
            }
            // if the token address doesn't exist yet
            if (!found) {
                // if the token is not in the list, add it
                tokens_buffer[tokenCount] = copy[i].paymentToken;
                // add the outstanding amount to the amounts array
                amounts_buffer[tokenCount] =
                    _outstandingTokenAmounts[copy[i].paymentToken];
                tokenCount++;
            }
        }

        // Delete all outstanding orders.
        delete _orders;

        // Prepare the arrays that will be sent back
        address[] memory tokens = new address[](tokenCount);
        uint[] memory amounts = new uint[](tokenCount);

        // iterate over newly populated amounts and tokens arrays
        for (uint i; i < tokenCount; ++i) {
            tokens[i] = tokens_buffer[i];
            amounts[i] = amounts_buffer[i];

            // Approve tokens to payment processor
            _ensureTokenAllowance(IPaymentProcessor_v1(_msgSender()), tokens[i]);

            // Ensure that the Client will have sufficient funds.
            // Note that while we also control when adding a payment order, more complex payment systems with
            // f.ex. deferred payments may not guarantee that having enough balance available when adding the order
            // means it'll have enough balance when the order is processed.
            _ensureTokenBalance(tokens[i]);
        }

        // Return copy of orders and orders' total token amount to payment
        // processor.
        return (copy, tokens, amounts);
    }
```

#### Process Payment Orders

- different logic per PaymentProcessor

##### PP_Simple_v1

- calls `collectPaymentOrders`, only uses the raw PaymentOrders
- executes every PaymentOrder one by one, straight up transferring each order
- if transfer was succesfull, outstandingTokenAmount on client is adjusted
- else the payment is added to a list of "unclaimable" payments

```solidity
function processPayments(IERC20PaymentClientBase_v1 client)
    external
    onlyModule
    validClient(client)
{
    // Collect outstanding orders and their total token amount.
    IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;

    // gets orders
    (orders,,) = client.collectPaymentOrders();

    // Transfer tokens from {IERC20PaymentClientBase_v1} to order recipients.
    address recipient;
    uint amount;
    uint len = orders.length;

    // iterates over orders
    for (uint i; i < len; ++i) {
        recipient = orders[i].recipient;
        address token_ = orders[i].paymentToken;
        amount = orders[i].amount;

        emit PaymentOrderProcessed(
            address(client),
            recipient,
            address(token_),
            amount,
            orders[i].start,
            orders[i].cliff,
            orders[i].end
        );

        // straight up sends token amount to recipient
        (bool success, bytes memory data) = token_.call(
            abi.encodeWithSelector(
                IERC20(token_).transferFrom.selector,
                address(client),
                recipient,
                amount
            )
        );

        // If call was success
        if (
            success && (data.length == 0 || abi.decode(data, (bool)))
                && token_.code.length != 0
        ) {
            emit TokensReleased(recipient, token_, amount);

            // Make sure to let paymentClient know that amount doesnt have to be stored anymore
            client.amountPaid(token_, amount);
        } else {
            emit UnclaimableAmountAdded(
                address(client), token_, recipient, amount
            );
            // Adds the walletId to the array of unclaimable wallet ids

            unclaimableAmountsForRecipient[address(client)][token_][recipient]
            += amount;
        }
    }
}
```

##### PP_Streaming_v1

```solidity
function processPayments(IERC20PaymentClientBase_v1 client)
    external
    onlyModule
    validClient(address(client))
{
    // We check if there are any new paymentOrders, without processing them
    if (client.paymentOrders().length > 0) {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        address[] memory tokens;
        uint[] memory totalAmounts;
        (orders, tokens, totalAmounts) = client.collectPaymentOrders();
        for (uint i = 0; i < tokens.length; i++) {
            if (
                IERC20(tokens[i]).balanceOf(address(client))
                    < totalAmounts[i]
            ) {
                revert
                    Module__PP_Streaming__InsufficientTokenBalanceInClient();
            }
        }

        // Generate Streaming Payments for all orders
        uint numOrders = orders.length;

        for (uint i; i < numOrders;) {
            _addPayment(
                address(client),
                orders[i],
                numStreams[address(client)][orders[i].recipient] + 1
            );

            emit PaymentOrderProcessed(
                address(client),
                orders[i].recipient,
                orders[i].paymentToken,
                orders[i].amount,
                orders[i].start,
                orders[i].cliff,
                orders[i].end
            );

            unchecked {
                ++i;
            }
        }
    }
}
```
