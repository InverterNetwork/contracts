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
`_triggerProposalCallback(funcData, op)` function.
The `op` argument specifies whether the callback is executed via `call` or
`delegatecall`, i.e. whether the callback is executed in the proposal's context
or the module's context.

### Callbacks executed in the Proposal's Context

In order to easily access the proposal's storage in a given proposal, callback functions are 
invoked via `delegatecall`, the *base module* contract inherits from the auto-generated
`ProposalStorage` contract (`src/generated/ProposalStorage.gen.sol`)
to mirror the proposal's storage layout.

All variables inherited from the `ProposalStorage` are prefixed with `__Proposal_` and declared as `internal` for convenience.

Per convention, such `delegatecall`-callbacks **SHOULD**:

1. Prefix the function name with `__Proposal_`
2. Only access `ProposalStorage` variables

In order to guarantee the callback is NOT executed in the module's context,
`wantProposalContext` modifier **MUST** be used!

An example for this could be:

```
function doSmth(
        uint256 dataNumber,
        string memory dataString,
    ) public returns(uint256,bool){
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(
                "__ExampleModule_doSmth(uint256,string)",
                dataNumber,
                dataString
            ),
            Types.Operation.DelegateCall
        );
        if (!ok) {
            revert Module_ProposalCallbackFailed();
        }
        return abi.decode(returnData, (uint256,bool));
    }

function __Proposal_doSmth(
        uint256 dataNumber,
        string memory dataString,
    ) external wantProposalContext returns(uint256){
        //do Smth in Proposalcontext
        doSmth(dataNumber, dataString);
        
        // Example return data:
        // return 1,true;
    }
```

### Callbacks executed in the Module's Context

Proposal callbacks executed in the module's context **MUST NOT** access
`__Proposal_` variables inherited from the `ProposalStorage` contract.

Per convention, the function name **SHOULD** be prefixed with `__Module_`.

Proposal callbacks executed in the module's context **MUST** be authenticated
via the `onlyProposal` modifier!

An example for this could be:

```
function doSmth(
        uint256 dataNumber,
        string memory dataString,
    ) external returns(uint256,bool){
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(
                "__ExampleModule_doSmth(uint256,string)",
                dataNumber,
                dataString
            ),
            Types.Operation.Call
        );
        if (!ok) {
            revert Module_ProposalCallbackFailed();
        }
        return abi.decode(returnData, (uint256,bool));
    }

function __ExampleModule_doSmth(
        uint256 dataNumber,
        string memory dataString,
    ) external onlyProposal returns(uint256,bool){
        //do Smth
        return 1,true;
    }
```

## Initialization

The contract provides a `__Module_init(proposal)` function for initialization
that **MUST** be called during the downstream module contract's `init()` function in order to
correctly initialize the storage.

The `init()` function is declared inside the base `Module` contract and,
therefore, has to be implemented inside the downstream contract.

### User Authentication

Users are authenticated using the proposal's `IAuthenticator` instance.
This ensures that all access management is handled solely by the proposal.
An Example for this could be:

```
// Define a role for contributors.
    bytes32 CONTRIBUTOR_ROLE =
        keccak256("milestoneContributor");

// Use a function to grant Role
__Module_proposal.grantRole(CONTRIBUTOR_ROLE, address);
```
