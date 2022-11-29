# Proposal.sol

## Things to know

1. A proposal is composed of a funding mechanism (FundingVault.sol), a set of contributors (ContributorManager.sol), and a set of modules (ModuleManager.sol).
2. Each proposal has a unique id.
3. The token being accepted for funding is non-changeable and set during initialization.
4. Authorizations are done via an IAuthorizer instance. This is also static and cannot be changed, once set.
5. Payments, which will be initiated by modules, are processed via a non-changeable {IPaymentProcessor} instance.

## Modifier(s)

### 1. onlyOwnerOrAuthorized

1. Modifier to guarantee function is only callable by authorized addresses.
2. Uses the IAuthorizer module to check authorized addresses.

## View Function(s)

### 1. version

`function version() external pure returns (string memory)`

Returns the version of the proposal instance.

### 2. owner

`function owner() public view override (OwnableUpgradeable, IProposal) returns (address)`

Returns the owner of the Proposal.

## Write Function(s)

### init

`function init( uint proposalId_, address owner_, IERC20 token_, address[] calldata modules, IAuthorizer authorizer_, IPaymentProcessor paymentProcessor_ ) external override (IProposal) initializer`

1. This function is used to initialize a proposal including the owner, Module Manager, Contribution Manager and Funding Vault.
2. The proposalID and token is set.
3. The Authorizer and the Payment Processor modules are added to the Proposal.

#### Parameters

1. uint proposalId_ -> An unsigned integer that will be used as the ID of the proposal being created
2. address owner_ -> Address of the owner of the proposal
3. IERC20 token_ -> IERC20 instance of the token which will be used for funding
4. address[] modules -> Array of addresses of modules which will be used in the proposal being created 
5. IAuthorizer authorizer_ -> IAuthorizer instance of the authorizer module which will be used for access control in the Proposal being created
6. IPaymentProcessor paymentProcessor_ -> IPaymentProcessor instance of the payment processor module which will be used to handle all aspects of payments in the proposal being created.

### executeTx

`function executeTx(address target, bytes memory data) external onlyOwnerOrAuthorized returns (bytes memory)`

Executes a call on target `target` with call data `data`. This function is only callable by authorized caller.

#### Parameters

1. address target -> The address to call
2. bytes data -> Calldata that will be used in the call

#### Return Data

1. bytes -> The return data of the call made in the function `executeTx`.