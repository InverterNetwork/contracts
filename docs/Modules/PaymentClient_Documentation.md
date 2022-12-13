# PaymentClient.sol

## Things to know
1. The PaymentClient mixin enables modules to create payment orders that are processable by a proposal's {IPaymentProcessor} module.
2. Mixins are libraries that are atomic units which are composable with other mixins and encapsulate the internal state variables and associated logic of a single, concrete, concept, providing internal constants and internal or private functions, which may be (typically) be associated with some structured data storage

## Modifier(s)

### 1. validRecipient(address recipient)

Modifier to ensure that the `recipient` is valid and is neither `address(0)` nor `address(PaymentClientContract)`.

### 2. validAmount(uint amount)

Modifier to ensure that the `amount` is non-zero.

### 3. validDueTo(uint dueTo)

Modifier to ensure that the due time is less than `block.timestamp`.

## View Function(s)

### 1. outstandingTokenAmount

`function outstandingTokenAmount() external view returns (uint);`

This function returns total outstanding token payment amount.

#### Return Data

1. total outstanding token payment amount.

### 2. paymentOrders

`function paymentOrders() external view returns (PaymentOrder[] memory);`

This function returns the list of outstanding payment orders.

#### Return Data

1. List of outstanding payment orders.

## Write Function(s)

### 1. collectPaymentOrders

`function collectPaymentOrders() external returns (PaymentOrder[] memory, uint);`

This function helps collect outstanding payment orders. Callable only by the proposal's IPaymentProcessor. This function returns the list of all payment orders.

This function ensures that the IPaymentProcessor is able to fetch all tokens from the initiator/creator of the orders by ensuring sufficient token allowance.

> NOTE: Collecting the payment orders means that the `IPaymentClient` will mark the orders as being fulfilled and delete them. The sole responsibility to actually fulfill the orders by transfering the tokens lies with the `IPaymentProcessor`.

#### Return data

1. list of payment orders
2. total amount of token to pay