# MilestoneManager.sol

## Things to know

1. This is a module to manage milestones for a proposal.
2. A milestone can exists in 4 different states:
    - added:
          The milestone got added to the contract.
    - active:
          When a milestone is started, it initias payment orders to pay
          the proposal's contributors.
          A milestone is active, until either its duration is over or it's
          marked as completed.
    - submitted:
          A proposal contributor marks a milestone as submitted by
          submitting non-empty data that can be interpreted and evaluated
          by off-chain systems.
    - completed:
          After a milestone was submitted, it can be marked as completed.
          This marks the end of the milestone.

## Modifier(s)

### 1. onlyContributor

Modifier to ensure that the `msg.sender` is a valid contributor or not.

### 2. validDuration(uint duration)

Modifier to ensure that the duration is non-zero.

### 3. validBudget(uint budget)

This modifier does not really do anything, lol. Can be changed to fit in the scope of the budget.

### 4. validTitle(string memory title_)

Modifier to ensure that the `title_` string is non-empty.

### 5. validDetails(string memory details)

Modifier to ensure that the `details` string is non-empty.

### 6. validSubmissionData(bytes calldata submissionData)

Modifier to ensure that the `submissionData` is non-empty

### 7. validId(uint id)

Modifier to ensure that the given `id` is valid and not already taken up.

### 8. onlyConsecutiveMilestones(uint prevId, uint id)

Modifier to ensure provided IDs are of consecutive milestones in the list of milestones

## View Function(s)

### 1. getMilestoneInformation

`function getMilestoneInformation(uint id) external view returns (Milestone memory);`

This function returns the milestone instance with id `id`. It will returns empty milestone in case id `id` is invalid.

#### Parameters

uint id -> The id of the milestone to return.

#### Return Data

1. Milestone with id `id`.

### 2. listMilestoneIds

`function listMilestoneIds() external view returns (uint[] memory);`

This function returns total list of milestone ids. The list is in ascending order.

#### Return Data

1. List of milestone ids.

### 3. getActiveMilestoneId

`function getActiveMilestoneId() external view returns (uint);`

This function returns the current active milestone's id. It will revert in case there is no active milestone.

#### Return Data

Current active milestone id.

### 4. hasActiveMilestone

`function hasActiveMilestone() external view returns (bool);`

This function returns whether there exists a current active milestone.

#### Return Data

True if current active milestone exists, false otherwise.

### 5. isNextMilestoneActivatable

`function isNextMilestoneActivatable() external view returns (bool);`

This function returns whether the next milestone is activatable.

#### Return Data

True if next milestone activatable, false otherwise.

### 6. isExisitingMilestoneId

`function isExistingMilestoneId(uint id) external view returns (bool);`

This function returns whether milestone with id `id` exists.

#### Return Data

True if milestone with id `id` exists, false otherwise.

## Write Function(s)

### 1. addMilestone

`function addMilestone(uint duration,uint budget,string memory title,string memory details) external returns (uint);`

This function adds a new milestone and is only callable by authorized addresses. Reverts if an argument invalid.

#### Parameters

1. uint duration -> duration The duration of the milestone.
2. uint budget -> budget The budget for the milestone.
3. string title -> title The milestone's title.
4. string details -> details The milestone's details.

#### Return Data

The newly added milestone's id.

### 2. removeMilestone

`function removeMilestone(uint prevId, uint id) external;`

#### Parameters

### 3. startNextMilestone

`function startNextMilestone() external;`

#### Parameters

### 4. updateMilestone

`function updateMilestone(uint id,uint duration,uint budget,string memory details) external;`

#### Parameters

### 5. submitMilestone

`function submitMilestone(uint id, bytes calldata submissionData) external;`

#### Parameters

### 6. completeMilestone

`function completeMilestone(uint id) external;`

#### Parameters

### 7. declineMilestone

`function declineMilestone(uint id) external;`

#### Parameters



