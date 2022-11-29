# ModuleManager.sol

## Things to know

1. This is a contract to manage modules that can execute transactions via this contract. Also used to manage own role-based access control mechanisms.
2. The role-based access control mechanism is based on [OpenZeppelin's AccessControl contract](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol).
3. Each module has it's own access control context which it is able to freely manage.

## Module(s)

### 1. __ModuleManager_onlyAuthorized

Modifier to ensure that `msg.sender` is authorized to mutate module manager's state.

### 2. onlyModule

Modifier to ensure that the `msg.sender` is a valid module. The `msg.sender` is in the `_modules` list and is neither address(0) nor the _SENTINEL address (used to denote the beginning or end of the list)

### 3. validModule(address module)

Modifier to ensure that the address `module` is a valid module. This is same as isModule_ check plus also checking if address `module` is not same as the address(ModuleManager).

### 4. isModule_(address module)

Modifier to ensure that the address `module` is a valid module. The `module` address is in the `_modules` list and is neither address(0) nor the _SENTINEL address(used to denote the beginning or end of the list).

### 5. isNotModule(address module)

Modifier to ensure that the address `module` is not a valid module.

### 6. onlyConsecutiveModules(address prevModule, address module)

Modifier to ensure that the `prevModule` and `module` addresses are consecutive in the modules' list.

## View Function(s)

## Write Function(s)