# ListAuthorizer.sol

## Things to know

1. This Module handles the authorization of several of the smart contract functions.
2. It keeps a list of authorized addresses and implements the IAuthorizers abstract function `isAuthorized`, necessary for the `onlyAuthorized` modifier in the base module contract.
3. The authorized addresses can be anything, ranging from an EOA to a Gnosis multisignature, keeping the module agnostic to the specific governance structure employed.

## Modifier(s)

No modifiers introduced in this contract.

## View Function(s)

### 1. isAuthorized

`function isAuthorized(address _who) public view override returns (bool)`

This function returns whether an address is authorized to facilitate the current transaction.

#### Parameters

1. address _who -> The address on which to perform the check.

#### Return Data

1. Whether address _who is authorized to carry out the given transaction or not

### 2. getAmountAuthorized

`function getAmountAuthorized() public view returns (uint)`

This function returns the number of authorized addresses

#### Return Data

1. Number of authorized addresses.

## Write Function(s)

### 1. addToAuthorized

`function addToAuthorized(address _who) external`

This function adds a new address to the list of authorized addresses.

#### Parameters

1. address _who -> The address to add to the list of authorized addresses.

### 2. __ListAuthorizer_removeFromAuthorized

`function __ListAuthorizer_removeFromAuthorized(address _who) public`

This function removes an address from the list of authorized addresses.

#### Parameters

1. address _who -> The address to remove from the list of authorized addresses.

### 3. removeFromAuthorized

`function removeFromAuthorized(address _who) external`

This function removes an address from the list of authorized addresses.

#### Parameters

1. address _who -> The address to remove from the list of authorized addresses.

### 4. __ListAuthorizer_transferAuthorization

`function __ListAuthorizer_transferAuthorization(address _from, address _to) public`

This function transfers authorization from the calling address to a new one.

#### Parameters

1. address _from -> The address to transfer the authorization from
2. address _to -> The address to transfer the authorization to

### 5. transferAuthorization

`function transferAuthorization(address _who) external`

This function transfers authorization from the calling address to a new one.

#### Parameters

1. address _who -> The address to transfer the authorization to

### 6. initialize

`function initialize(IProposal proposal, Metadata memory metadata) external`

This function calls the `__Module_init` function from the `Module.sol` contract thus initializing the module. 

Adds `msg.sender` as an authorized address and adds to the number of authorized addresses.

#### Parameter(s)

1. IProposal proposal -> The module's proposal instance.
2. Metadata metadata -> The module's metadata.
