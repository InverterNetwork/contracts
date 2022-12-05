# SingleVoteGovernance.sol

## Things to know

1. This contract implements a single vote governance module.
2. This contract keeps a list of authorized addresses and these addresses can create `Votes` wich other addresses can support or reject.
3. Votes are open for a set length of time. If they don't reach quorum at time of voting, they won't be able to be executed later, even if the quorum is lowered.
4. Each address can vote only once. Votes can not be modified.
5. The stored action can only be executed after the voting period ends, even if quorum was reached earlier.

## Modifier(s)

### 1. voteIsActive(uint _voteID)

Given the `_voteID`, this modifier verifies that a given vote is still active.

### 2. voteNotActive(uint _voteID)

Given the `_voteID`, this modifier verifies that a given vote is not active anymore.

### 3. quorumReached(uint _voteID)

Given the `_voteID`, this modifier verifies that a given vote did reach the quorum (at the time it was voted on).

### 4. validQuorum(uint8 _quorum, uint _amountAuthorized)

Given the `quorum` and `amountAuthorized`, this modifier verifies that the suggested quorum change wouldn't break the system

### 5. validModuleAddress(address _target)

Given the `_target`, this modifier verifies that the targeted module address is indeed active in the `Proposal`

### 6. validAction(bytes calldata _action)

Given the `_action`, this modifier verifies that the action to be executed after the vote is valid.

## View Function(s)

### 1. getRequiredQuorum

`function getRequiredQuorum() external view returns(uint8)`

This function returns the current required quorum.

#### Return Data

1. Current required quorum

### 2. getVoteDuration

`function getVoteDuration() external view returns (uint)`

This function returns the current voting duration

#### Return Data

1. Current Voting Duration

## Write Function(s)

### 1. initialize

`function initialize(IProposal proposal, uint8 _startingQuorum, uint _voteDuration, Metadata memory metadata) external`

This function initializes the module and then sets the `quorum` and `voteDuration`.

#### Parameters

1. IProposal proposal -> The module's proposal instance.
2. uint8 _startingQuorum -> The initial quorum. (The minimum number of votes that must be cast to make the voting valid.)
3. uint _voteDuration -> The duration for the votes
4. Metadata metadata -> The module's metadata.

### 2. __ListAuthorizer_removeFromAuthorized

`function __ListAuthorizer_removeFromAuthorized(address _who) public`

This function removes an address from the list of authorized addresses. The `validQuorum` modifier is added to `removeFromAuthorized` to make sure that removing users doesn't end up with unreachable quorum.

#### Parameters

1. address _who -> Address to remove authorization from

### 3. __Governance_changeQuorum

`function __Governance_changeQuorum(uint8 _new) external onlyProposal validQuorum(_new, getAmountAuthorized())`

This function helps set a new quorum.

#### Parameters

1. uint8 _new -> The new quorum

### 4. changeQuorum

`function changeQuorum(uint8 _new) external onlyProposal`

This function helps set a new quorum. It is Relay Function that routes the function call via the proposal. The `onlyProposal` modifier forces a quorum change to also go through governance.

#### Parameters

1. uint8 _new -> The new quorum

### 5. __Governance_changeVoteDuration

`function __Governance_changeVoteDuration(uint _new) external onlyProposal`

This function helps set a new vote duration. 

#### Parameters

1. uint _new -> The new vote duration

### 6. changeVoteDuration

`function changeVoteDuration(uint _new) external onlyProposal`

This function helps set a new vote duration. It is Relay Function that routes the function call via the proposal. The `onlyProposal` modifier forces a quorum change to also go through governance.

#### Parameters

1. uint _new -> The new vote duration

### 7. __Governance_createVote

`function __Governance_createVote( address _target, bytes calldata _encodedAction) external onlyProposal validModuleAddress(_target) validAction(_encodedAction)`

This function helps create a new `vote`.

#### Parameters

1. address _target -> The Module from which to execute the action
2. bytes _encodedAction -> The ABI encoded action to execute if it passes

### 8. createVote

`function createVote(address _target, bytes calldata _encodedAction) external onlyAuthorized`

This function helps create a new `vote`. It is Relay Function that routes the function call via the proposal.

#### Parameters

1. address _target -> The Module from which to execute the action
2. bytes _encodedAction -> The ABI encoded action to execute if it passes

### 9. __Governance_confirmAction

`function __Governance_confirmAction(address _voter, uint _voteID) external onlyProposal voteIsActive(_voteID)`

This function helps vote "yes" and execute action if quorum is reached.

#### Parameters

1. address _voter -> Address of voter
2. uint _voteID -> The ID of the vote to vote on

### 10. confirmAction

`function confirmAction(uint _voteID) external onlyAuthorized`

This function helps vote "yes" and execute action if quorum is reached. It is Relay Function that routes the function call via the proposal.

#### Parameters

1. uint _voteID -> The ID of the vote to vote on

### 11. __Governance_cancelAction

`function __Governance_cancelAction(address _voter, uint _voteID) external onlyProposal voteIsActive(_voteID)`

This function helps vote "no" and abort action if quorum is reached.

#### Parameters

1. address _voter -> Address of voter
2. uint _voteID -> The ID of the vote to vote on

### 12. cancelAction

`function cancelAction(uint _voteID) external onlyAuthorized`

This function helps vote "no" and abort action if quorum is reached. It is Relay Function that routes the function call via the proposal.

#### Parameters

1. uint _voteID -> The ID of the vote to vote on

### 13. __Governance_executeVote

`function __Governance_executeVote(uint _voteID) external onlyProposal quorumReached(_voteID) voteNotActive(_voteID)`

This function helps execute a vote. Only called by confirmAction once quorum is reached.

#### Parameters

1. uint _voteID -> The ID of the vote to vote on

### 14. executeVote

`function executeVote(uint _voteID) external voteIsActive(_voteID) quorumReached(_voteID)`

This function helps execute a vote. Only called by confirmAction once quorum is reached. It is Relay Function that routes the function call via the proposal.

#### Parameters

1. uint _voteID -> The ID of the vote to vote on