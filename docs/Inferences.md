# Inverter Contracts

# Notes for creating documentation

## Vision Statement

+ Larger projects and collaborations benefit immensely from multiple organizations being able to fund shared projects that lie outside the scope of any individual org. They could do this using a persistent, cross-DAO funding & resource distribution tool - enter, the Inverter.
+ Inverter Network aims to make long-term collaborative initiatives such as joint ventures, open source work, or research much simpler to get co-funded by reducing the administrative burden and; increasing accountability and transparency for both funders and contributor teams. 

## Inferences drawn from the existing doc

0. Assuming the proposal creator to be *he* for simplicity's sake.

1. **Trust Assumption** -> Modules need to be trusted by the proposal creator.

    1.1 Basically a proposal creator creates a proposal and then uses some (or all) of the available modules to implement what he wants in the proposal mechanisms. Therefore he needs to trust the module code implementations.

2. **Initialization** -> The modules are activated at the time of initializing the proposals and they can be deactivated at any time by authorized addresses. 

3. **Base Module Contract** -> 
    i. Trigerring and Receiving callbacks (via call and delegatecall) 
    ii. Authenticating the callers (via proposal's IAuthenticator)
> What is a callback?

> A callback function is a function passed into another function as an argument, which is then invoked inside the outer function to complete some kind of routine or action.
> Simply put it is the ability to pass along function types as parameters to other functions. A good example can be found in [this gist](https://gist.github.com/adamdossa/3c256ef52cf6f1c0329c8c9e71b74676)

4. **Difference between call and delegatecall** ->
+ When a *call* is made from contract A to contract B, contract A is the caller and tries to make changes into contract B via a *call* to a function contract B.
+ However, when a *delegatecall* is made from contract A to contract B, contract A is essentially giving permission to contract B to modify the storage of contract A according to the logic in contract B.
+ Ofcourse *delegatecall* is dangerous and care must be taken while using it.

5. **A design decision enabled by `delegatecall`** -> <br/>
A module should be able to always access any funds inside the proposal and take ownership of them by pulling them into their contract. This is achieved via delegatecall

6. With the understanding of point 4, we can say that a when a callback is triggered from a proposal by it's module it can either be executed in the context of the *proposal* (if called via `call`) or in the context of the *module* itself (if called via `delegatecall`)
+ To summarise: <br/>
    `delegatecall` -> changes in the caller's storage (module context) <br/>
    `call` -> changes in the callee storage (proposal context)
+ For convenience we have also used a `wantProposalContext` modifier.
+ To ensure that a function is callable only via delegatecall, we use the wantProposalContext modifier

### What even is Module context and Proposal context

1. Based on my limited understanding till now:

+ Anyhow if a call can affect the storage of the Proposal contract, it is the Proposal context
+ Alternatively, if the msg.sender *seems* to be the Proposal contract, it is the Proposal context

+ Anyhow if a call can affect the storage of the Module contract, it is the Module context
+ Alternatively, if the msg.sender *seems* to be the Module contract, it is the Module context.

2. Proposal Context -> `delegatecall` -> `wantProposalContext` modifier -> `__Proposal_` prefix -> only `ProposalStorage` vars accessible
+ Explanation: A module uses the triggerProposalCallback function inherited from Module.sol. This function calls the Proposal, which in turn calls back to the Module via delegatecall. So the call executed in the Module is called via delegatecall from the Proposal, therefore in the Proposal's context

3. Module Context -> `call` -> `onlyProposal` modifier -> `__Module_` prefix -> `ProposalStorage` vars inaccisible 

### Initialization

1. You must implement the `init` function in your downstream modules to correctly initialize the storage.

### User Authentication

1. Users are authenticated using the proposal's `IAuthenticator` instance.
2. All access management is handled solely by the proposal.