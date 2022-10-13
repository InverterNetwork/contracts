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

    /// @dev Function is only callable by contributor.
    error OnlyCallableByContributor();

    /// @dev Invalid title.
    error InvalidTitle();

    /// @dev Invalid startDate.
    error InvalidStartDate();

    /// @dev Invalid details.
    error InvalidDetails();

    /// @dev There is no milestone with this id.
    error InvalidMilestoneId();

    /// @dev The new milestone id is not yet available.
    error NewMilestoneIdNotYetAvailable();

    /// @dev The milestone with the given id is already created.
    error MilestoneWithIdAlreadyCreated();

    /// @dev The milestone is not yet submitted.
    error MilestoneNotSubmitted();

    /// @dev The milestone is already completed.
    error MilestoneAlreadyCompleted();

    /// @dev The milestone is removed.
    error MilestoneRemoved();

    //--------------------------------------------------------------------------
    // Events

    /// @dev New Milestone was created
    event NewMilestone(string title, uint startDate, string details);

    /// @dev A Milestone was changed in regards of startDate or details
    event ChangeMilestone(uint id, uint startDate, string details);

    /// @dev A Milestone was changed in regards of startDate
    event ChangeStartDate(uint id, uint startDate);

    /// @dev A Milestone was changed in regards of details
    event ChangeDetails(uint id, string details);

    /// @notice A Milestone was removed
    event RemoveMilestone(uint id);

    /// @notice A Milestone was submitted
    event SubmitMilestone(uint id);

    /// @notice A submitted Milestone was confirmed
    event ConfirmMilestone(uint id);

    /// @notice A submitted Milestone was declined
    event DeclineMilestone(uint id);

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
    function milestone(uint id) external view returns (Milestone memory);

    // @todo felix, mp: Docs + rename.
    function nextNewMilestoneId() external view returns (uint);

    //----------------------------------
    // Milestone Mutating Functions

    /// @notice Adds a new milestone.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param newId The id of the new milestone.
    /// @param title The title for the new milestone.
    /// @param startDate The starting date of the new milestone.
    /// @param details The details of the new milestone.
    function addMilestone(
        uint newId,
        string memory title,
        uint startDate,
        string memory details
    ) external;

    /// @notice Changes a milestone's details.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    /// @param details The new details of the milestone.
    function changeDetails(uint id, string memory details) external;

    /// @notice Changes a milestone's starting date.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    /// @param startDate The new starting date of the milestone.
    function changeStartDate(uint id, uint startDate) external;

    /// @notice Removes a milestone.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function removeMilestone(uint id) external;

    /// @notice Submits a milestone.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function submitMilestone(uint id) external;

    /// @notice Confirms a submitted milestone.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function confirmMilestone(uint id) external;

    /// @notice Declines a submitted milestone.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function declineMilestone(uint id) external;
}
