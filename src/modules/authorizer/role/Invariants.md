# Requirement Invariants

- Let Workflow owners define the restrictions of the functions themselves
- Hierarchical Roles
- Public Roles
- Renounce all Authorization
- Tranfer your own Role to another address
- Forward has role to external contracts
- Start directly with roles in a module
- Module Roles vs Global Roles
- Label Role Name to id
- Only allow functions to be called for created Roles

# Technology Invariants

- Its not possible to delete a Role
- Naming a Role is to lable it
- A role can be renamed by overriding the label (takes a transaction though)
  - Might be something we should make clear on the frontend side
- Module has to be added to Orchestrator before it is intialized now
- Modules v1 are not compatible with orchestrator v2 because of interface check when adding modules
- Modules v2 are not compatible with orchestrator v1 because of interface check when adding modules

# To Discuss:

- Workflow admin naming
  // Hierarchical Roles //@todo We dont have the full definition of what this entails
