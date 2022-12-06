# PaymentProcessor.sol

## Things to know

1. The PaymentProcessor is a module to process payment orders from other modules. 
2. In order to process a module's payment orders, the module must implement the {IPaymentClient} interface.

## Modifier(s)

This contract does not define any modifiers.

## View Function(s)

### 1. token

`function token() external view returns (IERC20);`

Returns the IERC20 token the payment processor can process.

#### Return Data

1. IERC20 token that the payment processor can process.

## Write Function(s)

### 1. processPayment

`function processPayments(IPaymentClient client) external;`

Processes all payments from an {IPaymentClient} instance. It's up to the the implementation to keep up with what has been paid out or not.

#### Parameters

1. IPaymentClient client -> The {IPaymentClient} instance to process its to payments.