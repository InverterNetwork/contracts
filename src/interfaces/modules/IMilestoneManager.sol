// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IMilestoneManager {
    //--------------------------------------------------------------------------
    // Types

    struct Milestone {
        uint startDate;
        bool submitted;
        bool completed;
        bool removed;
        string title;
        string details;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by contributor.
    error Module__MilestoneManager__OnlyCallableByContributor();

    /// @notice Given title invalid.
    error Module__MilestoneManager__InvalidTitle();

    /// @notice Given startDate invalid.
    error Module__MilestoneManager__InvalidStartDate();

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

    /// @notice Given milestone not confirmable.
    error Module__MilestoneManager__MilestoneNotConfirmable();

    /// @notice Given milestone not declineable.
    error Module__MilestoneManager__MilestoneNotDeclineable();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new milestone added.
    event MilestoneAdded(
        uint indexed id, string title, uint startDate, string details
    );

    /// @notice Event emitted when a milestone's startDate updated.
    event MilestoneStartDateUpdated(uint indexed id, uint startDate);

    /// @notice Event emitted when a milestone's details updated.
    event MilestoneDetailsUpdated(uint indexed id, string details);

    /// @notice Event emitted when a milestone removed.
    event MilestoneRemoved(uint indexed id);

    /// @notice Event emitted when a milestone submitted.
    event MilestoneSubmitted(uint indexed id);

    /// @notice Event emitted when a milestone confirmed.
    event MilestoneConfirmed(uint indexed id);

    /// @notice Event emitted when a milestone declined.
    event MilestoneDeclined(uint indexed id);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // Access Control

    /// @notice The contributor access control role.
    function CONTRIBUTOR_ROLE() external view returns (bytes32);

    /// @notice Grants contributor role to account `account`.
    /// @dev There is no reach around function included, because the proposal
    ///      is involved anyway.
    /// @param account The address to grant the role.
    function grantContributorRole(address account) external;

    /// @notice Revokes contributor role from account `account`.
    /// @dev There is no reach around function included, because the proposal
    ///      is involved anyway.
    /// @param account The address to revoke the role from.
    function revokeContributorRole(address account) external;

    //----------------------------------
    // Milestone View Functions

    /// @notice Returns the milestone with id `id`.
    /// @dev Returns empty milestone in case id `id` is invalid.
    /// @param id The id of the milstone to return.
    /// @return Milestone with id `id`.
    function getMilestone(uint id) external view returns (Milestone memory);

    //----------------------------------
    // Milestone Mutating Functions

    /// @notice Adds a new milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param title The title for the new milestone.
    /// @param startDate The starting date of the new milestone.
    /// @param details The details of the new milestone.
    /// @return The newly added milestone's id.
    function addMilestone(
        string memory title,
        uint startDate,
        string memory details
    ) external returns (uint);

    /// @notice Changes a milestone's details.
    /// @dev Only callable by authorized addresses.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    /// @param details The new details of the milestone.
    function updateMilestoneDetails(uint id, string memory details) external;

    /// @notice Changes a milestone's starting date.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid or milestone already removed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    /// @param startDate The new starting date of the milestone.
    function updateMilestoneStartDate(uint id, uint startDate) external;

    /// @notice Removes a milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid or milestone already completed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function removeMilestone(uint id) external;

    /// @notice Submits a milestone.
    /// @dev Only callable by addresses holding the contributor role.
    /// @dev Reverts if id invalid or milestone already removed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function submitMilestone(uint id) external;

    // @todo mp, felix: Should be renamed to `completeMilestone()`?

    /// @notice Confirms a submitted milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone already removed, or milestone not
    ///      yet submitted.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function confirmMilestone(uint id) external;

    /// @notice Declines a submitted milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone already removed, milestone not
    ///      yet submitted, or milestone already completed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function declineMilestone(uint id) external;
}
