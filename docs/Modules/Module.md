# Module.sol

File: [Module.sol](../../src/modules/base/Module.sol)

## Things to know

1. This contract acts as the base contract for modules.
2. This contract provides a framework for triggering and receiving proposal callbacks (via `call`)
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
`{ProposalStorage}`, the module's own state is never mutated.
It's therefore safe to not authenticate the caller in these functions. A function only accessing the proposal storage variables, as recommended, can not alter it's own module's storage.
Advised to use function prefix `__Proposal_`.

### 3. onlyProposal

Modifier to guarantee function is only callable by the proposal. `onlyProposal` functions MUST only access the module's storage, i.e. `__Module_` variables. Advised to use function prefix `__Module_`

## View Function(s)

### 1. identifier

`function identifier() external view returns (bytes32);`

Returns the module's identifier. The identifier is defined as the keccak256 hash of the module's abi packed encoded major version, url and title.

#### Return Data

1. Returns the module's identifier. (Each module is identified via a unique identifier based on its major version, title, and url given in the metadata.)

### 2. version

`function version() external view returns (uint, uint);`

This function returns the module's version.

#### Return data

1. The module's major version.
2. The module's minor version.

### 3. url

`function url() external view returns (string memory);`

This function returns the module's URL.

#### Return data

1. The module's URL.

### 4. title

`function title() external view returns (string memory);`

This function returns the module's title.

#### Return data

1. The module's title.

### 5. proposal

`function proposal() external view returns (IProposal);`

This function returns the module's {IProposal} proposal instance.

#### Return data

1. The module's proposal.

## Write Function(s)

### 1. init

`function init( IProposal proposal, Metadata memory metadata, bytes memory configdata) external;`

The module's initializer function. CAN be overriden by downstream contract. MUST call `__Module_init()`.

#### Parameter(s)

1. `IProposal proposal` -> The module's proposal instance.
2. `Metadata metadata` -> The module's metadata.
3. `bytes configdata` -> Variable config data for specific module implementations.

### 2. pause

`function pause() external;`

Pauses the module. Only callable by authorized addresses.

### 3. unpause

`function unpause() external;`

Unpauses the module. Only callable by authorized addresses.

## Extra Explanation

This is a section of documentation that breaks down the Module documentation in more granular details.

## Modules

Modules are used within the Proposal Inverter to implement specific business
logic that can be added to a proposal during it's initilization.

## Trust assumptions

Modules must be trusted by the proposal creator.

## Initilization

Modules are activated in a proposal during its initialization.
They can be deactivated by authorized addresses at any time.

## The Base Module Contract

The base Module contract (`src/modules/base/Module.sol`) provides a framework
for triggering and receiving proposal callbacks (via `call`)
and a modifier to authenticate callers via the module's proposal using the
`IAuthorizer` interface.

### Proposal Callbacks

A module can trigger a callback from its proposal via the internal
`_triggerProposalCallback(funcData, op)` function.
The callback is executed via `call` in the module's context.

### Callbacks executed in the Module's Context

Proposal callbacks executed in the module's context **MUST NOT** access
`__Proposal_` variables inherited from the `ProposalStorage` contract.

Per convention, the function name **SHOULD** be prefixed with `__Module_`.

Proposal callbacks executed in the module's context **MUST** be authenticated
via the `onlyProposal` modifier!

An example for this could be:

```solidity
function doSmth(
    uint256 dataNumber,
    string memory dataString,
) external returns(uint256,bool){
    bool ok;
    bytes memory returnData;

    (ok, returnData) = _triggerProposalCallback(
        abi.encodeWithSignature(
            "__Module_doSmth(uint256,string)",
            dataNumber,
            dataString
        )
    );

    if (!ok) {
        revert Module_ProposalCallbackFailed();
    }
    return abi.decode(returnData, (uint256,bool));
}

function __Module_doSmth(
    uint256 dataNumber,
    string memory dataString,
) external onlyProposal returns(uint256,bool){
    // Function is exeucted in module's context. Only proposal is able to call
    // the function.
    return (1, true);
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
