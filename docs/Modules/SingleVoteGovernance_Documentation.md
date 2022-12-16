# SingleVoteGovernance.sol

## Things to know

1. This contract implements a single vote governance module.
2. This contract keeps a list of authorized addresses and these addresses can create `Votes` wich other addresses can support or reject.
3. Votes are open for a set length of time. If they don't reach quorum at time of voting, they won't be able to be executed later, even if the quorum is lowered.
4. Each address can vote only once. Votes can not be modified.
5. The stored action can only be executed after the voting period ends, even if quorum was reached earlier.

## Modifier(s)

### 1. onlySelf

This modifier ensures that the `msg.sender` is not the same as the `SingleVoteGovernor` contract (address this).

### 2. onlyVoter

This modifier ensures that the `msg.sender` is an authorised voter (member of the mapping `isVoter`).

## View Function(s)

### 1. isAuthorized

`function isAuthorized(address who) public view returns (bool);`

This function checks whether the address `who` is authorized or not.

#### Parameter(s)

1. address who -> The address whose authorization you want to check.

#### Return Data

1. bool -> True if address `who` is authorized(), false otherwise.

> NOTE: The governance contract (`SingleVoteGovernance.sol`) itself is only authorized.

### 2. getReceipt

`function getReceipt(uint _ID, address voter) public view returns (Receipt memory);`

> NOTE 1: `Receipt` is the a struct containing `bool hasVoted` and `uint8 support`.
> NOTE 2: `Motion` is a struct with the following structure:
`    struct Motion {
        // Execution data.
        address target;
        bytes action;
        // Governance data.
        uint startTimestamp;
        uint endTimestamp;
        uint requiredQuorum;
        // Voting result.
        uint forVotes;
        uint againstVotes;
        uint abstainVotes;
        mapping(address => Receipt) receipts;
        // Execution result.
        uint executedAt;
        bool executionResult;
        bytes executionReturnData;
    }`

This function helps to fetch the `Receipt` (see `NOTE 1` above) of the `Motion`(see `NOTE 2` above) with id of `_ID` and associated with address `voter`. 

#### Parameter(s)

1. uint _ID -> The identifying number of the `Motion` for which you want to see the `Receipt`.
2. address voter -> Given the `_ID` of the `Motion`, the address of the voter for which you want to see the `Receipt`.

#### Return Data

1. Receipt -> A `Receipt` of the address `voter` from the `Motion` with id `_ID`.

### 3. MAX_DURATION_DURATION

`function MAX_VOTING_DURATION() external view returns (uint);`

#### Return Data

1. uint -> The maximum duration for voting, which is currently hardcodd to `2 weeks`.

### 4. MIN_VOTING_DURATION

`function MIN_VOTING_DURATION() external view returns (uint);`

#### Return Data

1. uint -> The minimum duration for voting, which is currently hardcoded to `1 days`.

## Write Function(s)

### 1. initialize

`function initialize(IProposal proposal, uint8 _startingQuorum, uint _voteDuration, Metadata memory metadata) external`

This function initializes the module and then sets the `quorum` and `voteDuration`.

#### Parameters

1. IProposal proposal -> The module's proposal instance.
2. uint8 _startingQuorum -> The initial quorum. (The minimum number of votes that must be cast to make the voting valid.)
3. uint _voteDuration -> The duration for the votes
4. Metadata metadata -> The module's metadata.

### 2. setQuorum

`function setQuorum(uint newQuorum) external;`

#### Parameter(s)

### 3. setVotingDuration

`function setVotingDuration(uint newVoteDuration) external;`

#### Parameter(s)

1. uint newVoteDuration -> 

### 4. addVoter

`function addVoter(address who) external;`

#### Parameter(s)

1. address who ->

### 5. removeVoter

`function removeVoter(address who) external;`

#### Parameter(s)

1. address who -> 

### 6. transferVotingRights

`function transferVotingRights(address to) external;`

#### Parameter(s)

1. address to -> 

### 7. createMotion

`function createMotion(address target, bytes calldata action) external returns (uint);`

#### Parameter(s)

1. address target ->
2. bytes action ->

#### Return Data

1. uint -> 

### 8. castVote

`function castVote(uint motionId, uint8 support) external;`

#### Parameter(s)

1. uint motionId ->
2. uint8 support ->

### 9. executeMotion

`function executeMotion(uint motionId) external;`

#### Parameter(s)

1. uint motionId -> 