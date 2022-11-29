# Module.sol

## Things to know

1. This contract acts as the base contract for modules.
2. This contract provides a framework for triggering and receiving proposal callbacks (via `call` or `delegatecall`)
3. This contract also provides a modifier to authenticate callers via the module's proposal.
4. Each module is identified via a unique identifier based on its major version, title, and url given in the metadata.
5. Modules will automatically be updated incase of minor updates, however they won't be automatically updated in case of major updates

## Modifier(s)

### 1. onlyAuthorized 

Modifier to guarantee function is only callable by addresses authorized via Proposal.
`onlyAuthorized` functions SHOULD only be used to trigger callbacks from the proposal via the `_triggerProposalCallback()` function.

### 2. wantProposalContext

Modifier to guarantee that the function is not executed in the module's context.
As long as wantProposalContext-protected functions only access the proposal storage variables (`__Proposal_`) inherited from
{ProposalStorage}, the module's own state is never mutated.
It's therefore safe to not authenticate the caller in these functions. A function only accessing the proposal storage variables, as recommended, can not alter it's own module's storage.
Advised to use function prefix `__Proposal_`.

### 3. onlyProposal

Modifier to guarantee function is only callable by the proposal. `onlyProposal` functions MUST only access the module's storage, i.e. `__Module_` variables. Advised to use function prefix `__Module_`

## View Function(s)

## Write Function(s)

### 1. init

`function init( IProposal proposal, Metadata memory metadata, bytes memory configdata) external;`

The module's initializer function. CAN be overriden by downstream contract. MUST call `__Module_init()`.

#### Parameter(s)

1. IProposal proposal -> The module's proposal instance.
2. Metadata metadata -> The module's metadata.
3. bytes configdata -> Variable config data for specific module implementations.

### 2. pause

`function pause() external;`

Pauses the module. Only callable by authorized addresses.

### 3. unpause

`function unpause() external;`

Unpauses the module. Only callable by authorized addresses.