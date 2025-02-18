# Requirement Invariants

- Label Role Name to id
- Only allow functions to be called for created Roles
- Let Workflow owners define the restrictions of the functions themselves
- Public Roles
- Hierarchical Roles
- Renounce all Authorization
- Tranfer your own Role to another address
- Forward has role to external contracts // We removed that
- Start directly with roles in a module
- Can start directly with public roles in a module
- Its possible to add a module Admin that can add function restrictions to module

# Technology Invariants

- Its not possible to delete a Role
- Naming a Role is to label it
- A role can be renamed by overriding the label (takes a transaction though)
  - Might be something we should make clear on the frontend side
- Module has to be added to Orchestrator before it is intialized now
- Modules v1 are not compatible with orchestrator v2 because of interface check when adding modules
- Modules v2 are not compatible with orchestrator v1 because of interface check when adding modules

# todo

- enable sub Roles to change function selectors

  -> @todo Check for orchestrator Admin restrictions in getFee functions and such

- Workflow admin naming -> Call it that way
  // Hierarchical Roles //@todo We dont have the full definition of what this entails

# To Discuss:

- Decision on saving names onchain

- Separation of concerns: Sometimes the system will have several actors which need to operate different parts of it with guarantees towards each other. It should be possible to set up roles that are "out of reach" from an administrator/owner, or even completely immutable.
  -> Multisig for Admin
  -> Voting Roles
  -> @todo Check for orchestrator Admin restrictions in getFee functions and such
