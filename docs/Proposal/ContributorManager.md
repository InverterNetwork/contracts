# ContributorManager.sol
File: [ContributorManager.sol](../../src/proposal/base/ContributorManager.sol)

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

Modifier to ensure that the `who` address is valid. The `who` address should not be `address(0)`, `address(0x1)` or `address(ContributorManager)`.

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

1. `address who` -> The address (which is a valid `Contributor`) for which you need information

#### Return Data

1. `Contributor` -> Contributor instance of the address `who`

### 2. isContributor

`function isContributor(address who) public view returns (bool)`

Returns whether the address `who` is a contributor.

#### Parameter(s)

1. `address who` -> The address for which you want to check whether it is a contributor or not.

#### Return Data

1. `bool` -> Returns true if `who` was a contributor otherwise returns false.

### 3. listContributor

`function listContributors() external view returns (address[] memory)`

Returns the list of addresses of current contributors.

#### Return Data

address[] -> An array of addresses of valid contributors.

### 4. contributorsSize

`function contributorsSize() external view returns (uint)`

Returns the number of contributors.

#### Return Data

`uint` -> Number of contributors.

### 5. getPreviousContributor

`function getPreviousContributor(address who) external view returns (address previousContributor);`

This function fetches the id of the previous Contributor in the list and reverts if `who` is invalid. 
This function should ideally be called from the front-end or from any off-chain source since running this on-chain would result in a lot of gas consumption owing to O(n) runtime.

#### Parameter(s)

1. `address who` -> The address of which the previous element in the list should be found.

#### Return Data

1. The address of the previous Contributor.

## Write Function(s)

### 1. addContributor

`function addContributor(address who, string memory name, string memory role, uint salary) external __ContributorManager_onlyAuthorized isNotContributor(who) validAddress(who) validName(name) validRole(role) validSalary(salary)`

Adds address `who` as a new contributor. This function is only callable by authorized addresses and reverts if an argument invalid.

#### Parameters

1. `address who` -> The address `who` that is to be added as a contributor
2. `string name` -> The contributor's name
3. `string role` -> The contributor's role
4. `uint salary` -> The contributor's salary

### 2. removeContributor

`function removeContributor(address prevContrib, address who) external __ContributorManager_onlyAuthorized isContributor_(who)
 onlyConsecutiveContributors(prevContrib, who)`

Removes address `who` from being a contributor. This function is only callable by authorized addresses and reverts if `who` not a contributor. Function also reverts if `prevContrib` is not the previous element in the contributor's list.

#### Parameters

1. `address prevContrib` -> The previous contributor in the contributor's list.
2. `address who` -> The contributor's address to remove.

### 3. updateContributor

`function updateContributor(address who, string memory role, uint salary) external __ContributorManager_onlyAuthorized isContributor_(who) validRole(role) validSalary(salary)`

Updates `who` role and/or salary. This function is only callable by authorized addresses and reverts if the `role` or `salary` parameter is invalid.

#### Parameters

1. `address who` -> The contributor's address.
2. `string role` -> The contributor's new role.
3. `uint salary` -> The contributor's new salary.

### 4. revokeContributor

`function revokeContributor(address prevContrib) external isContributor_(_msgSender()) onlyConsecutiveContributors(prevContrib, _msgSender())`

Revokes the caller from being a contributor.

#### Parameters

1. `address prevContrib` -> The previous contributor in the contributor's list.

