pragma solidity ^0.8.13;

// Internal Dependencies
import {Types} from "src/common/Types.sol";

import {Module} from "./base/Module.sol";

import {IProposal} from "src/interfaces/IProposal.sol";

/// @dev Invalid Title
error InvalidTitle();

/// @dev Invalid startDate
error InvalidStartDate();

/// @dev Invalid details
error InvalidDetails();

/// @dev There is no milestone with this id
error InvalidMilestoneId();

/// @dev The Milestone is not yet submitted
error MilestoneNotSubmitted();

/// @dev The Milestone is already completed
error MilestoneCompleted();

/// @dev The Milestone is removed
error MilestoneRemoved();

contract MilestoneModule is Module {
    //--------------------------------------------------------------------------------
    // STRUCTS

    struct Milestone {
        string title; //@note Could go with a name/hash
        uint256 startDate;
        string details; //@note Could go instead with an ipfs hash or a link
        bool submitted;
        bool completed;
        bool removed;
    }

    //--------------------------------------------------------------------------------
    // STATE
    /// @dev Mapping of all Milestones
    ///      uses nextNewMilestoneId to determine positioning of the milestones
    mapping(uint256 => Milestone) public milestones;

    /// @dev The Id the next new Milestone is assigned
    uint256 nextNewMilestoneId;

    //--------------------------------------------------------------------------------
    // EVENTS

    /// @dev New Milestone was created
    event NewMilestone(string title, uint256 startDate, string details);

    /// @dev A Milestone was changed in regards of startDate or details
    event ChangeMilestone(uint256 id, uint256 startDate, string details);

    /// @notice A Milestone was removed
    event RemoveMilestone(uint256 id);

    /// @notice A Milestone was submitted
    event SubmitMilestone(uint256 id);

    /// @notice A submitted Milestone was confirmed
    event ConfirmMilestone(uint256 id);

    /// @notice A submitted Milestone was declined
    event DeclineMilestone(uint256 id);

    //--------------------------------------------------------------------------------
    // MODIFIER

    /// @dev Checks via the governance module if msg.sender is contributor
    modifier contributorAccess() {
        //@todo Correct Governance Link here
        _;
    }

    /// @dev Checks if the given title is valid
    /// @param title : given milestone title
    modifier validTitle(string memory title) {
        //@todo test modifier
        if ((bytes(title)).length == 0) {
            revert InvalidTitle();
        }
        _;
    }

    /// @dev Checks if the given startDate is valid.
    /// @param startDate : The given startDate of the milestone
    modifier validStartDate(uint256 startDate) {
        /* if () {//@note Do we need restrictions here?
         revert InvalidStartDate();
       } */
        _;
    }

    /// @dev Checks if the given details is valid.
    /// @param details : The given details of the milestone
    modifier validDetails(string memory details) {
        if ((bytes(details)).length == 0) {
            revert InvalidDetails();
        }
        _;
    }

    /// @dev Checks if the given id is available in the milestone array
    /// @param id : id in the milestone array
    modifier validId(uint256 id) {
        if (id >= nextNewMilestoneId) {
            revert InvalidMilestoneId();
        }
        _;
    }

    ///@dev Checks if the given Milestone is submitted, but not completed
    ///@param id : id in the milestone array
    modifier submittedNotCompleted(uint256 id) {
        if (!milestones[id].submitted) {
            revert MilestoneNotSubmitted();
        }
        if (milestones[id].completed) {
            revert MilestoneCompleted();
        }
        _;
    }

    ///@dev Checks if the given Milestone is removed
    ///@param id : id in the milestone array
    modifier notRemoved(uint256 id) {
        if (milestones[id].removed) {
            revert MilestoneCompleted();
        }
        _;
    }

    //++++++++++++++++++++++++++++++++++++++++++ CONSTRUCTOR ++++++++++++++++++++++++++++++++++++++++++

    constructor() {}

    /// @notice insitializes the MilestoneModule
    /// @dev Removed initializer because the underlying __Module_init() is initializer
    /// @param proposal : The proposal that should be linked to this module
    function initialize(IProposal proposal) external initializer {
        __Module_init(proposal);
        //@todo Set PayableModule
    }

    //++++++++++++++++++++++++++++++++++++++++++ FUNCTIONS ++++++++++++++++++++++++++++++++++++++++++

    ///@dev Adds a milestone to the milestone array
    ///@param title : the title for the new milestone
    ///@param startDate : the startDate of the new milestone
    ///@param details : the details of the new milestone
    ///@return id : the id of the new milestone in the milestone array
    function __Milestone_addMilestone(
        string memory title,
        uint256 startDate, //@note Possible Startdate now
        string memory details
    )
        external
        onlyProposal
        validTitle(title)
        validStartDate(startDate)
        validDetails(details)
        returns (uint256 id)
    {
        milestones[nextNewMilestoneId++] = Milestone(
            title,
            startDate,
            details,
            false,
            false,
            false
        );
        emit NewMilestone(title, startDate, details);
        return nextNewMilestoneId - 1;
    }

    ///@notice Adds a milestone to the milestone array
    ///@dev Relay Function that routes the function call via the proposal
    ///@param title : the title for the new milestone
    ///@param startDate : the startDate of the new milestone
    ///@param details : the details of the new milestone
    ///@return id : the id of the new milestone in the milestone array
    function addMilestone(
        string memory title,
        uint256 startDate, //Possible Startdate now
        string memory details
    ) external onlyAuthorized returns (uint256 id) {
        bytes memory returnData = _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_addMilestone(string,uint256,string)",
                title,
                startDate,
                details
            ),
            Types.Operation.Call
        );
        return abi.decode(returnData, (uint256));
    }

    ///@dev Changes a milestone in regards of startDate or details
    ///@param id : id in the milestone array
    ///@param startDate : the new startDate of the given milestone
    ///@param details : the new details of the given milestone
    function __Milestone_changeMilestone(
        uint256 id,
        uint256 startDate,
        string memory details
    )
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        validStartDate(startDate)
        validDetails(details)
    {
        Milestone memory oldMilestone = milestones[id]; //@note it might be more efficient use storage
        milestones[id] = Milestone(
            oldMilestone.title, //Keep old title
            startDate,
            details,
            oldMilestone.submitted, //Keep submitted Status
            oldMilestone.completed, //Keep completed Status
            oldMilestone.removed //Keep completed Status
        );
        emit ChangeMilestone(id, startDate, details);
    }

    ///@notice Changes a milestone in regards of startDate or details
    ///@dev Relay Function that routes the function call via the proposal
    ///@param id : id in the milestone array
    ///@param startDate : the new startDate of the given milestone
    ///@param details : the new details of the given milestone
    function changeMilestone(
        //@note We might want to split up into Specific Changes (changeDetails ....)
        uint256 id,
        uint256 startDate,
        string memory details
    ) external onlyAuthorized validId(id) {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_changeMilestone(uint256,uint256,string)",
                id,
                startDate,
                details
            ),
            Types.Operation.Call
        );
    }

    ///@dev removal of the milestone
    ///@param id : id in the milestone array
    function __Milestone_removeMilestone(
        uint256 id //@note There might be a point made to increase the level of interaction required to remove a milestone
    ) external onlyProposal validId(id) notRemoved(id) {
        milestones[id].removed = true; //@todo you still can interact with milestone although hes removed -> Modifier

        emit RemoveMilestone(id);
    }

    ///@notice removal of the milestone
    ///@dev Relay Function that routes the function call via the proposal
    ///@param id : id in the milestone array
    function removeMilestone(uint256 id) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Milestone_removeMilestone(uint256)", id),
            Types.Operation.Call
        );
    }

    // Programmer submitMilestone:
    // 1: I want to change the milestone submit field to True.
    // 2: I want the milestone submit field to BE True.

    ///@dev Submit a milestone
    ///@param id : id in the milestone array
    function __Milestone_submitMilestone(uint256 id)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
    // @audit Function should be idempotent!
    // HTTP: GET, POST, DELETE, ADD
    //            ^^^^  ^^^^^^  XXX->Id
    {
        Milestone storage milestone = milestones[id];

        if (!milestone.submitted) {
            milestone.submitted = true;
            emit SubmitMilestone(id);
        }
    }

    ///@notice Submit a milestone
    ///@dev Relay Function that routes the function call via the proposal
    ///@param id : id in the milestone array
    function submitMilestone(uint256 id) external contributorAccess {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Milestone_submitMilestone(uint256)", id),
            Types.Operation.Call
        );
    }

    ///@dev Confirms a submitted milestone
    ///@param id : id in the milestone array
    function __Milestone_confirmMilestone(uint256 id)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        submittedNotCompleted(id)
    {
        Milestone storage milestone = milestones[id];
        milestone.completed = true;

        //milestone.submitted = true; //@note Change this to false?

        //@note Maybe move the milestone to a seperate array as mark of completion?
        //@todo add Payment

        emit ConfirmMilestone(id);
    }

    ///@notice Confirms a submitted milestone
    ///@dev Relay Function that routes the function call via the proposal
    ///@param id : id in the milestone array
    function confirmMilestone(uint256 id) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_confirmMilestone(uint256)",
                id
            ),
            Types.Operation.Call
        );
    }

    ///@dev Declines a submitted milestone
    ///@param id : id in the milestone array
    function __Milestone_declineMilestone(uint256 id)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        submittedNotCompleted(id)
    {
        Milestone storage milestone = milestones[id];
        milestone.submitted = false;

        emit DeclineMilestone(id);
    }

    ///@notice Declines a submitted milestone
    ///@dev Relay Function that routes the function call via the proposal
    ///@param id : id in the milestone array
    function declineMilestone(uint256 id) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_declineMilestone(uint256)",
                id
            ),
            Types.Operation.Call
        );
    }
}
