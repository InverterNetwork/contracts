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



## Write Function(s)




