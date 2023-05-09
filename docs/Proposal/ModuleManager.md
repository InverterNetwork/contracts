# ModuleManager.sol

File: [ModuleManager.sol](../../src/proposal/base/ModuleManager.sol)

## Things to know

1. This is a contract to manage modules that can execute transactions via this contract. Also used to manage own role-based access control mechanisms.
2. The role-based access control mechanism is based on [OpenZeppelin's AccessControl contract](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol).
3. Each module has it's own access control context which it is able to freely manage.

## Modifier(s)

### 1. \_\_ModuleManager_onlyAuthorized

Modifier to ensure that `msg.sender` is authorized to mutate module manager's state.

### 2. onlyModule

Modifier to ensure that the `msg.sender` is a valid module. The `msg.sender` is in the `_modules` list

### 3. validModule(address module)

Modifier to ensure that the address `module` is a valid module. This is same as isModule\_ check plus also checking if address `module` is not same as the address(ModuleManager).

### 4. isModule\_(address module)

Modifier to ensure that the address `module` is a valid module. The `module` address is in the `_modules` list.

### 5. isNotModule(address module)

Modifier to ensure that the address `module` is not a valid module.

## View Function(s)

### 1. hasRole

`function hasRole(address module, bytes32 role, address account) external returns (bool);`

Returns whether the account `account` holds the role `role` in the module's `module` access control context.

#### Parameter(s)

1. `address module` -> The module in which's access control context the role is checked.
2. `bytes32 role` -> The access control role.
3. `address account` -> The account to check role for.

#### Return Data

`bool` -> Returns true if the account `account` holds the role `role` in the module's `module` access control context else returns `false`.

### 2. isModule

`function isModule(address module) external returns (bool);`

Returns whether the address `module` is added as module.

#### Parameter(s)

1. `address module` -> The module to check.

#### Return Data

`bool` -> True if address `module` was a valid module else false.

### 3. listModules

`function listModules() external view returns (address[] memory);`

Returns the list of all modules.

#### Return Data

`address[]` -> the array of addresses containing valid modules.

### 4. modulesSize

`function modulesSize() external view returns (uint);`

Returns the number of modules.

#### Return Data

`uint` -> the number of modules.

#### Parameter(s)

1. `address module` -> The address of which the previous element in the list should be found.

#### Return Data

1. `address previousModule` -> The address of the previous module.

## Write Function(s)

### 1. addModule

`function addModule(address module) external;`

Adds address `module` as module. This function is only callable by authorized address and fails if address is invalid or address already added as module.

#### Parameter(s)

1. `address module` -> The module address to add.

### 2. removeModule

`function removeModule(address module) external;`

Removes address `module` as module. This function is only callable by authorized address and fails if address not added as module.

#### Parameter(s)

1. `address module` -> The module address to remove.

### 3. executeTxFromModule

`function executeTxFromModule(address to, bytes memory data) external returns (bool, bytes memory);`

Executes a call to `to` with call data `data` either via call. This function is only callable by enabled modules.

#### Parameter(s)

1. `address to` -> The address where we need to make a call.
2. `bytes data` -> The call data to be sent with the call.

#### Return Data

1. `bool` -> Boolean indicating whether the call succeeded.
2. `bytes` -> The return data of the call (in bytes).

### 4. grantRole

`function grantRole(bytes32 role, address account) external;`

Grants role `role` to account `account` in caller's access control context. This function is only callable by enabled module.

#### Parameter(s)

1. `bytes32 role` -> The access control role.
2. `address account` -> The account to revoke role for.

### 5. revokeRole

`function revokeRole(bytes32 role, address account) external;`

Revokes role `role` from account `account` in caller's access control context. This function is only callable by enabled module.

#### Parameter(s)

1. `bytes32 role` -> The access control role.
2. `address account` -> The account to revoke role for.

### 6. renounceRole

`function renounceRole(address module, bytes32 role) external;`

Renounces the caller's role `role` in module's `module` access control context.

#### Parameter(s)

1. `address module` -> The module in which's access control context the role should be renounced.
2. `bytes32 role` -> The access control role.
