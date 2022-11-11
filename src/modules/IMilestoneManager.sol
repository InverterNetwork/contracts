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
        ///      That is the number of tokens payed during the milestone's
        ///      duration.
        ///      CAN be zero.
        uint budget;
        /// @dev The timestamp the milestone started.
        uint startTimestamp;
        /// @dev Whether the milestone got submitted already.
        ///      Note that only accounts holding the {CONTRIBUTOR_ROLE()} can
        ///      submit milestones.
        bool submitted;
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

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by contributor.
    error Module__MilestoneManager__OnlyCallableByContributor();

    /// @notice Given duration invalid.
    error Module__MilestoneManager__InvalidDuration();

    // @todo mp, nuggan, marvin: Add error for invalid Budget here if necessary.

    /// @notice Given title invalid.
    error Module__MilestoneManager__InvalidTitle();

    /// @notice Given details invalid.
    error Module__MilestoneManager__InvalidDetails();

    /// @notice Given milestone id invalid.
    error Module__MilestoneManager__InvalidMilestoneId();

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

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new milestone added.
    event MilestoneAdded(
        uint indexed id,
        uint duration,
        uint budget,
        string title,
        string details
    );

    /// @notice Event emitted when a milestone got updated.
    event MilestoneUpdated(
        uint indexed id, uint duration, uint budget, string details
    );

    /// @notice Event emitted when a milestone removed.
    event MilestoneRemoved(uint indexed id);

    /// @notice Event emitted when a milestone submitted.
    event MilestoneSubmitted(uint indexed id);

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

    //----------------------------------
    // Milestone Mutating Functions

    /// @notice Adds a new milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid.
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param title The milestone's title.
    /// @param details The milestone's details.
    /// @return The newly added milestone's id.
    function addMilestone(
        uint duration,
        uint budget,
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

    // @todo startNextMilestone function doc.
    /// @dev Only callable by authorized addresses.
    function startNextMilestone() external;

    /// @notice Updates a milestone's informations.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid or milestone already started.
    /// @param id The milestone's id.
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param details The milestone's details.
    function updateMilestone(
        uint id,
        uint duration,
        uint budget,
        string memory details
    ) external;

    /// @notice Submits a milestone.
    /// @dev Only callable by addresses holding the contributor role.
    /// @dev Reverts if id invalid, milestone not yet started, or milestone
    ///      already completed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function submitMilestone(uint id) external;

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
