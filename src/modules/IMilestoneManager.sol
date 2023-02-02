// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IPaymentClient} from "src/modules/mixins/IPaymentClient.sol";

interface IMilestoneManager is IPaymentClient {
    //--------------------------------------------------------------------------
    // Types

    struct Milestone {
        /// @dev The duration of the milestone.
        ///      MUST not be zero.
        uint duration;
        /// @dev The budget for the milestone.
        ///      That is the number of tokens payed to contributors when the
        ///      milestone starts.
        ///      CAN be zero.
        uint budget;
        /// @dev The contributors for the Milestone
        ///      MUST not be empty
        ///      All contributors.salary MUST add up to 100_000_000 (100%)
        Contributor[] contributors;
        /// @dev The timestamp the milestone started.
        uint startTimestamp;
        /// @dev Represents the data that is accompanied when a milestone is submitted.
        ///      A Milestone is interpreted as being submitted when the
        ///      submissionData bytes array is not empty.
        ///      Note that only accounts holding the {CONTRIBUTOR_ROLE()} can
        ///      set submittedData and therefore submit milestones.
        bytes submissionData;
        /// @dev Whether the milestone is completed.
        ///      A milestone is completed if it got confirmed and started more
        ///      than duration seconds ago.
        bool completed;
        /// @dev The milestone's title.
        ///      MUST not be empty.
        string title;
        /// @dev The milestone's details.
        ///      MUST not be empty.
        string details;
    }

    struct Contributor {
        /// @dev The contributor's address.
        ///      MUST not be empty.
        address addr;
        /// @dev The contributor's salary, as a percentage of the Milestone's total budget.
        ///      MUST not be empty.
        ///      MUST be a number between 1 and SALARY_PRECISION.
        /// @dev Default value for SALARY_PRECISION is 100_000_000 This allows precision of up to 1$ in a 1.000.000$ budget.
        uint salary;
        /// @dev Additional data for the contributor.
        ///      CAN be empty.
        bytes32 data;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by contributor.
    error Module__MilestoneManager__OnlyCallableByContributor();

    /// @notice Given duration invalid.
    error Module__MilestoneManager__InvalidDuration();

    // @audit-info If needed, add error for invalid budget here.
    /// @notice Given budget invalid.
    //error Module__MilestoneManager__InvalidBudget();

    /// @notice Given title invalid.
    error Module__MilestoneManager__InvalidTitle();

    /// @notice Given details invalid.
    error Module__MilestoneManager__InvalidDetails();

    /// @notice Given milestone id invalid.
    error Module__MilestoneManager__InvalidMilestoneId();

    /// @dev The given submissionData is invalid
    error Module__MilestoneManage__InvalidSubmissionData();

    /// @notice Given milestone not updateable.
    error Module__MilestoneManager__MilestoneNotUpdateable();

    /// @notice Given milestone not removable.
    error Module__MilestoneManager__MilestoneNotRemovable();

    /// @notice Given milestone not submitable.
    error Module__MilestoneManager__MilestoneNotSubmitable();

    /// @notice Given milestone not completed.
    error Module__MilestoneManager__MilestoneNotCompleteable();

    /// @notice Given milestone not declineable.
    error Module__MilestoneManager__MilestoneNotDeclineable();

    /// @notice Given milestone not activateable.
    error Module__MilestoneManager__MilestoneNotActivateable();

    /// @notice The supplied milestones are not consecutive
    error Module__MilestoneManager__MilestonesNotConsecutive();

    /// @notice No active milestone currently existing.
    error Module__MilestoneManager__NoActiveMilestone();

    /// @notice Milestone could not be started as there are no contributors.
    error Module__MilestoneManager__NoContributors();

    /// @notice Given contributor address invalid.
    error Module__MilestoneManager__InvalidContributorAddress();

    /// @notice Contributor address is already on list.
    error Module__MilestoneManager__DuplicateContributorAddress();

    /// @notice Given contributor salary invalid.
    error Module__MilestoneManager__InvalidContributorSalary();

    /// @notice Given contributor salary invalid.
    error Module__MilestoneManager__InvalidSalarySum();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new milestone added.
    event MilestoneAdded(
        uint indexed id,
        uint duration,
        uint budget,
        Contributor[] contributors,
        string title,
        string details
    );

    /// @notice Event emitted when a milestone got updated.
    event MilestoneUpdated(
        uint indexed id,
        uint duration,
        uint budget,
        Contributor[] contributors,
        string details
    );

    /// @notice Event emitted when a milestone is removed.
    event MilestoneRemoved(uint indexed id);

    /// @notice Event emitted when a milestone is submitted.
    event MilestoneSubmitted(uint indexed id, bytes submissionData);

    /// @notice Event emitted when a milestone is completed.
    event MilestoneCompleted(uint indexed id);

    /// @notice Event emitted when a milestone declined.
    event MilestoneDeclined(uint indexed id);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // Milestone View Functions

    /// @notice Returns the milestone instance with id `id`.
    /// @dev Returns empty milestone in case id `id` is invalid.
    /// @param id The id of the milstone to return.
    /// @return Milestone with id `id`.
    function getMilestoneInformation(uint id)
        external
        view
        returns (Milestone memory);

    /// @notice Returns total list of milestone ids.
    /// @dev List is in ascending order.
    /// @return List of milestone ids.
    function listMilestoneIds() external view returns (uint[] memory);

    /// @notice Fetches the id of the previous milestone in the list
    /// @dev Reverts if id invalid
    /// @dev This should ideally be only used in a frontend context
    ///      because iterating through the list and finding the previous element
    ///      causes an O(n) runtime of the given list and should ideally be outsourced off-chain.
    /// @param id the id of which the previous element in the list should be found.
    /// @return prevId The id of the previous milestone.
    function getPreviousMilestoneId(uint id)
        external
        view
        returns (uint prevId);

    /// @notice Returns the current active milestone's id.
    /// @dev Reverts in case there is no active milestone.
    /// @return Current active milestone id.
    function getActiveMilestoneId() external view returns (uint);

    /// @notice Returns whether there exists a current active milestone.
    /// @return True if current active milestone exists, false otherwise.
    function hasActiveMilestone() external view returns (bool);

    /// @notice Returns whether the next milestone is activatable.
    /// @return True if next milestone activatable, false otherwise.
    function isNextMilestoneActivatable() external view returns (bool);

    /// @notice Returns whether milestone with id `id` exists.
    /// @return True if milestone with id `id` exists, false otherwise.
    function isExistingMilestoneId(uint id) external view returns (bool);

    /// @notice Returns whether an address is a contributor in one specific milestone.
    /// @return True if the address is a contributor, false otherwise.
    function isContributor(uint id, address who) external view returns (bool);

    //----------------------------------
    // Milestone Mutating Functions

    /// @notice Adds a new milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid.
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param contributors The contributor information for the milestone
    /// @param title The milestone's title.
    /// @param details The milestone's details.
    /// @return The newly added milestone's id.
    function addMilestone(
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        string memory title,
        string memory details
    ) external returns (uint);

    /// @notice Removes a milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone already completed or milestone ids
    ///      not consecutive in list.
    /// @param prevId The previous milestone's id in the milestone list.
    /// @param id The milestone's id to remove.
    function removeMilestone(uint prevId, uint id) external;

    /// @notice Starts the next milestones.
    /// @dev Creates the payment orders to pay contributors.
    /// @dev Reverts if next milestone not activatable or proposal's contributor
    ///      list empty.
    /// @dev Only callable by authorized addresses.
    function startNextMilestone() external;

    /// @notice Updates a milestone's informations.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid or milestone already started.
    /// @param id The milestone's id.
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param contributors The contributor information for the milestone
    /// @param details The milestone's details.
    function updateMilestone(
        uint id,
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        string memory title,
        string memory details
    ) external;

    /// @notice Submits a milestone.
    /// @dev Only callable by addresses holding the contributor role.
    /// @dev Reverts if id invalid, milestone not yet started, or milestone
    ///      already completed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function submitMilestone(uint id, bytes calldata submissionData) external;

    /// @notice Completes a milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid or milestone not yet submitted.
    /// @param id The milestone's id.
    function completeMilestone(uint id) external;

    /// @notice Declines a submitted milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone not yet submitted, or milestone
    ///      already completed.
    /// @param id The milestone's id.
    function declineMilestone(uint id) external;
}
