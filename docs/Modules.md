# Modules

Modules are used within the Proposal Inverter to implement specific business
logic that can be added to a proposal during it's initilization.

## Trust assumptions

Modules must be trusted by the proposal creator.

## Initilization

Modules are activated in a proposal during its initialization.
They can be deactivated by authorized addresses at any time.

## The Base Module Contract

The base Module contract (`src/modules/base/Module.sol`) provides a framework
for triggering and receiving proposal callbacks (via `call` or `delegatecall`)
and a modifier to authenticate callers via the module's proposal using the
`IAuthorizer` interface.

### Proposal Callbacks

A module can trigger a callback from its proposal via the internal
`triggerProposalCallback(funcData, op)` function.
The `op` argument specifies whether the callback is executed via `call` or
`delegatecall`, i.e. whether the callback is executed in the proposal's context
or the module's context.

### Callbacks executed in the Proposal's Context

In order to easily access the proposal's storage in proposal callback functions
invoked via `delegatecall`, the contract inherits from the auto-generated
`ProposalStorage` contract (`src/generated/ProposalStorage.sol`)
to mirror the proposal's storage layout.

All variables inherited from the `ProposalStorage` are prefixed with `__Proposal_`.

Per convention, such `delegatecall`-callbacks **SHOULD**:
1. Prefix the function name with `__Proposal_`
2. Only access `ProposalStorage` variables

In order to guarantee the callback is NOT executed in the module's context,
`wantProposalContext` modifier **MUST** be used!

### Callbacks executed in the Module's Context

Proposal callbacks executed in the module's context **MUST NOT** access
`__Proposal_` variables inherited from the `ProposalStorage` contract.

Per convention, the function name **SHOULD** be prefixed with `__Module_`.

Proposal callbacks executed in the module's context **MUST** be authenticated
via the `onlyProposal` modifier!

### Initialization

The contract provides a `__Module_init(proposal)` function for initialization
that **MUST** be called during the dowmstream's `init()` function order to
correctly initialize the storage.

The `init()` function is declared inside the base `Module` contract and,
therefore, has to be implemented inside the downstream contract.

### User Authentication

Users are authenticated using the proposal's `IAuthenticator` instance.
This ensures that all access management is handled solely by the proposal.

TODO: Docs that the beacon proxy pattern is used for modules.
TODO: Docs about versioning and other module meta data.
