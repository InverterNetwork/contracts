# ContributorManager.sol

## Things to know

1. This is a contract to manage a list of contributors.
2. It saves the assigned role, name, and salary of each contributor in a registry, and manages a list of contributors in the style of the Gnosis Safe's [OwnerManager](https://github.com/safe-global/safe-contracts/blob/main/contracts/base/OwnerManager.sol).
3. Along each contributor address, the contract stores a salary, name, and role.
4. This module is responsible for off-chain retrieval of team assignment or similar information and NOT for access control.
5. Each contributor is represented only once and is therefore unique.

## Modifier(s)

### 1. __ContributorManager_onlyAuthorized

Modifier to ensure that the `msg.sender` is authorized to mutate contributor manager's state.

### 2. validAddress(address who)

Modifier to ensure that the `who` address is valid. The `who` address should not be address(0), address(0x1) or address(ContributorManager).

### 3. validName(string memory name)

Modifier to ensure that the `name` is a valid string (string empty check)

### 4. validRole(string memory role)

Modifier to check if the given `role` is legitimate or not (string empty check)

### 5. validSalary(uint salary)

Modifier to ensure a non-zero salary

### 6. isContributor_(address who)

Modifier to ensure `who` is a contributor

### 7. isNotContributor(address who)

Modifier to ensure that a function is not callable by a `contributor`

### 8. onlyConsecutiveContributors(address prevContrib, address contrib)

Modifier to ensure that `prevContrib` and `contrib` are consecutive contributors and not the same contributor.

## View Function(s)

### 1. getContributorInformation

`function getContributorInformation(address who) external view isContributor_(who) returns (Contributor memory)`

Returns the registerted `Contributor` instance for address `who`.

#### Parameter(s)

1. address who -> The address (which is a valid `Contributor`) for which you need information

#### Return Data

1. Contributor -> Contributor instance of the address `who`

### 2. isContributor

`function isContributor(address who) public view returns (bool)`

Returns whether the address `who` is a contributor.

#### Parameter(s)

1. address who -> The address for which you want to check whether it is a contributor or not.

#### Return Data

1. bool -> Returns true if `who` was a contributor otherwise returns false.

### 3. listContributor

`function listContributors() external view returns (address[] memory)`

Returns the list of addresses of current contributors.

#### Return Data

address[] -> An array of addresses of valid contributors.

### 4. contributorsSize

`function contributorsSize() external view returns (uint)`

Returns the number of contributors.

#### Return Data

uint -> Number of contributors.