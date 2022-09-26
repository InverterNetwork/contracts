
# The base Module Contract 

 The base Module contract provides a framework for triggering and receiving proposal
 callbacks (via `call` or `delegatecall`) and a modifier to authenticate callers via the module's proposal.

The contract can be found under ```/src/modules/base/Module.sol```. 


 # Proposal Callbacks

 A module can trigger a callback from its proposal via the internal `triggerProposalCallback(funcData, op)` function.
 The `op` argument specifies whether the callback is executed via `call` or `delegatecall`, i.e. whether the callback is executed in the proposal's or the module's context.


 ## Callbacks executed in the Proposal's Context

 In order to easily access the proposal's storage in proposal callback functions executed via `delegatecall`, the contract inherits from the auto-generated {ProposalStorage} contract to mirror the proposal's storage layout. 

 All variables inherited from the {ProposalStorage} are prefixed with `__Proposal_`.

 Per convention, such `delegatecall`-callbacks SHOULD:
  1. Prefix the function name with `__Proposal_`
  2. Only access {ProposalStorage} variables.


 **In order to guarantee the callback is not executed in the module's context, the `wantProposalContext` modifier MUST be used!**


 ## Callbacks executed in the Module's Context

 Proposal callbacks executed in the module's context MUST NOT access `__Proposal_` variables.

 Per convention, the function name SHOULD be prefixed with `__Module_`.

 **Proposal callbacks executed in the module's context MUST be authenticated via the `onlyProposal` modifier.**

 # Initialization

 The contract provides a `__Module_init(proposal)` function for initialization that MUST be called in order to correctly initialize the storage.


 # User Authentication

 Users are authenticated using the proposal's {IAuthenticator} instance. This ensures that all access management is handled solely by the proposal.