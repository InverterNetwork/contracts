# Comments authorizer Update

# Onchain Roles setup Questions

- Find concept for proper role setup
  - Questions:
    - What is the exact userstory here?
  - Idea: createRoleAndAddAccessPermissions setup function
    - function that returns input parameters needed for createRoleAndAddAccessPermissions
    - least intrusive into code
      - example function
        - createWhitelistRoleTemplate
          - parameters
            - members\_ (address[])
          - returns
            - roleName: WHITELIST_ROLE
            - respectiveAdminRole: DEFAULT_ADMIN_ROLE
            - initialMembers: members\_
            - targets: address[address(this)]
            - selectors: bytes4[][buy.selector,sell.selector]();
  - Idea: directly call createRoleAndAddAccessPermissions from Module
    - needs to modify the function itself to allow for module calls

## Did do:

- Restructured the File into Role Management and Authorization

  - Added a section for possibly deprecated functions

- Added functionalities in authorizer

  - Keys field
    - function restrictions
  - Role Id counter
    - Controlled Role Creation
  - HasPermission
    - Default Admin can always call
    - Public Role can always call
      - Public role is role key with bytes32.max
      - Handles like any other key/roleId/role
    - uses Keys field
      - if caller has any of roles within can call
  - Role label for name
    - Otherwise unique identifier by id
  - addAccessPermission
    - Only role with DEFAULT_ADMIN_Role can add keys
  - compact addRole and restrictions

- added to module
  - locked modifier
    - uses hasPermission from authorizer
    - with function data -> function selector

## Notes

- bytes32 to uint conversion is a bit of a hassle
  - can be used interchangeably most of the time

## Planned

- Authorizer
  - scrap module roles
  - scrap global roles
  - Restrict grantRole Function to only existing roles (within counter range)
- Module
- scrap grant roles from module
- scrap ModuleRoleModifier
- scrap onlyOrchestrator modifier
- scrapOnlyOrchestratorAdmin modifier

## Implications for current Workflows

- Current Roles will persist between upgrades

## Questions

## Going forward

- proposed naming for locks
- onlyDefaultAdmin/OnlyOrchestratorAdmin -> locked modifier?
- integrate mehmet into typical workflow interactions
