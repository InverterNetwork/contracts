pragma solidity ^0.8.13;

// Internal Dependencies
import {Types} from "src/common/Types.sol";

import {Module} from "./base/Module.sol";

import {IProposal} from "src/interfaces/IProposal.sol";

contract MilestoneModule is Module {
    /// @dev This function is only callable by a contributor
    error OnlyCallableByContributor();

    /// @dev Invalid Title
    error InvalidTitle();

    /// @dev Invalid startDate
    error InvalidStartDate();

    /// @dev Invalid details
    error InvalidDetails();

    /// @dev There is no milestone with this id
    error InvalidMilestoneId();

    /// @dev The new Milestone Id is not yet available
    error NewMilestoneIdNotYetAvailable();

    /// @dev The Milestone with the given Id is already created
    error MilestoneWithIdAlreadyCreated();

    /// @dev The Milestone is not yet submitted
    error MilestoneNotSubmitted();

    /// @dev The Milestone is already completed
    error MilestoneAlreadyCompleted();

    /// @dev The Milestone is removed
    error MilestoneRemoved();

    //--------------------------------------------------------------------------------
    // STRUCTS

    struct Milestone {
        string title;
        uint256 startDate;
        string details;
        bool submitted;
        bool completed;
        bool removed;
    }

    //--------------------------------------------------------------------------------
    // STATE

    // Define a role for contributors.
    bytes32 public constant MILESTONE_CONTRIBUTOR_ROLE =
        keccak256("milestoneContributor");

    /// @dev Mapping of all Milestones
    ///      uses nextNewMilestoneId to determine positioning of the milestones
    mapping(uint256 => Milestone) public milestones;

    /// @dev The Id the next new Milestone is assigned
    uint256 public nextNewMilestoneId;

    //--------------------------------------------------------------------------------
    // EVENTS

    /// @dev New Milestone was created
    event NewMilestone(string title, uint256 startDate, string details);

    /// @dev A Milestone was changed in regards of startDate or details
    event ChangeMilestone(uint256 id, uint256 startDate, string details);

    /// @dev A Milestone was changed in regards of startDate
    event ChangeStartDate(uint256 id, uint256 startDate);

    /// @dev A Milestone was changed in regards of details
    event ChangeDetails(uint256 id, string details);

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
        if (
            !__Module_proposal.hasRole(
                address(this),
                MILESTONE_CONTRIBUTOR_ROLE,
                msg.sender
            )
        ) {
            revert OnlyCallableByContributor();
        }
        _;
    }

    /// @dev Checks if the given title is valid
    /// @param title : given milestone title
    modifier validTitle(string memory title) {
        if ((bytes(title)).length == 0) {
            revert InvalidTitle();
        }
        _;
    }

    /// @dev Checks if the given startDate is valid.
    /// @param startDate : The given startDate of the milestone
    modifier validStartDate(uint256 startDate) {
        /* if () {//@note not in vergangenheit
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

    /// @dev Checks if the given newId is valid.
    /// @param newId :
    modifier newMilestoneIdAvailable(uint256 newId) {
        if (newId > nextNewMilestoneId) {
            revert NewMilestoneIdNotYetAvailable();
        }
        _;
    }

    /// @dev Invalid NewId
    error InvalidNewId();

    ///@dev Checks if the given Milestone is submitted
    ///@param id : id in the milestone array
    modifier submitted(uint256 id) {
        if (!milestones[id].submitted) {
            revert MilestoneNotSubmitted();
        }
        _;
    }

    ///@dev Checks if the given Milestone is not completed
    ///@param id : id in the milestone array
    modifier notCompleted(uint256 id) {
        if (milestones[id].completed) {
            revert MilestoneAlreadyCompleted();
        }
        _;
    }

    ///@dev Checks if the given Milestone is removed
    ///@param id : id in the milestone array
    modifier notRemoved(uint256 id) {
        if (milestones[id].removed) {
            revert MilestoneRemoved();
        }
        _;
    }

    //++++++++++++++++++++++++++++++++++++++++++ CONSTRUCTOR ++++++++++++++++++++++++++++++++++++++++++

    constructor() {}

    /// @notice insitializes the MilestoneModuleS
    /// @param proposal_ : The proposal that should be linked to this module
    function initialize(IProposal proposal_) external initializer {
        __Module_init(proposal_);
        //@todo Set PayableModule
    }

    //++++++++++++++++++++++++++++++++++++++++++ FUNCTIONS ++++++++++++++++++++++++++++++++++++++++++

    /// @notice Grants an address the role of Milestone
    /// @dev There is no reach around function included, because the proposal is involved anyway
    /// @param account the address that is granted the role
    function grantMilestoneContributorRole(address account)
        public
        onlyAuthorized
    {
        __Module_proposal.grantRole(MILESTONE_CONTRIBUTOR_ROLE, account);
    }

    /// @notice Grants an address the role of Milestone
    /// @dev There is no reach around function included, because the proposal is involved anyway
    /// @param account the address that is granted the role
    function revokeMilestoneContributorRole(address account)
        public
        onlyAuthorized
    {
        __Module_proposal.revokeRole(MILESTONE_CONTRIBUTOR_ROLE, account);
    }

    /// @dev Adds milestone to the milestone mapping
    /// @dev
    /// @param newId : the id of the new milestone
    /// @param title : the title for the new milestone
    /// @param startDate : the startDate of the new milestone
    /// @param details : the details of the new milestone
    function __Milestone_addMilestone(
        uint256 newId,
        string memory title,
        uint256 startDate, //@note Possible Startdate now
        string memory details
    )
        external
        onlyProposal
        validTitle(title)
        validStartDate(startDate)
        validDetails(details)
        newMilestoneIdAvailable(newId) //@todo test
    {
        if (newId == nextNewMilestoneId) {
            milestones[nextNewMilestoneId++] = Milestone(
                title,
                startDate,
                details,
                false,
                false,
                false
            );
            emit NewMilestone(title, startDate, details);
        } else {
            //If its not the same Milestone Content give an error message
            if (!(hasSameMilestoneContent(newId, title, startDate, details))) {
                revert MilestoneWithIdAlreadyCreated();
            }
        }
    }

    /// @notice Adds a milestone to the milestone array
    /// @dev Relay Function that routes the function call via the proposal
    /// @param newId : the id of the new milestone
    /// @param title : the title for the new milestone
    /// @param startDate : the startDate of the new milestone
    /// @param details : the details of the new milestone
    function addMilestone(
        uint256 newId,
        string memory title,
        uint256 startDate, //Possible Startdate now
        string memory details
    ) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback( //@todo check for okay everywhere?
            abi.encodeWithSignature(
                "__Milestone_addMilestone(uint256,string,uint256,string)",
                newId,
                title,
                startDate,
                details
            ),
            Types.Operation.Call
        );
        if (!ok) {
            revert Module_ProposalCallbackFailed();
        }
    }

    ///@dev Changes a milestone in regards of details
    ///@param id : id in the milestone array
    ///@param details : the new details of the given milestone
    function __Milestone_changeDetails(
        uint256 id,
        string memory details
    ) external onlyProposal validId(id) notRemoved(id) validDetails(details) {
        Milestone storage milestone = milestones[id];

        if (keccak256(bytes(milestone.details)) != keccak256(bytes(details))) {
            milestone.details = details;
            emit ChangeDetails(id, details);
        }
    }

    ///@notice Changes a milestone in regards of details
    ///@dev Relay Function that routes the function call via the proposal
    ///@param id : id in the milestone array
    ///@param details : the new details of the given milestone
    function changeDetails(uint256 id, string memory details)
        external
        onlyAuthorized
    {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_changeDetails(uint256,string)",
                id,
                details
            ),
            Types.Operation.Call
        );
    }

    ///@dev Changes a milestone in regards of startDate
    ///@param id : id in the milestone array
    ///@param startDate : the new startDate of the given milestone
    function __Milestone_changeStartDate(uint256 id, uint256 startDate)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        validStartDate(startDate)
    {
        Milestone storage milestone = milestones[id];

        if (milestone.startDate != startDate) {
            milestone.startDate = startDate;
            emit ChangeStartDate(id, startDate);
        }
    }

    ///@notice Changes a milestone in regards of startDate
    ///@dev Relay Function that routes the function call via the proposal
    ///@param id : id in the milestone array
    ///@param startDate : the new startDate of the given milestone
    function changeStartDate(uint256 id, uint256 startDate)
        external
        onlyAuthorized
    {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_changeStartDate(uint256,uint256)",
                id,
                startDate
            ),
            Types.Operation.Call
        );
    }

    ///@dev removal of the milestone
    ///@param id : id in the milestone array
    function __Milestone_removeMilestone(
        uint256 id //@note There might be a point made to increase the level of interaction required to remove a milestone
    ) external onlyProposal validId(id) notRemoved(id) notCompleted(id) {
        Milestone storage milestone = milestones[id];

        if (!milestone.removed) {
            milestone.removed = true;
            emit RemoveMilestone(id);
        }
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
        submitted(id)
        notCompleted(id)
    {
        Milestone storage milestone = milestones[id];
        if (!milestone.completed) {
            milestone.completed = true;

            //@note pay who and how much?
            //@todo add Payment

            emit ConfirmMilestone(id);
        }
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
    function __Milestone_declineMilestone(
        uint256 id //@note maybe at why declined
    )
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        submitted(id)
        notCompleted(id)
    {
        Milestone storage milestone = milestones[id];
        if (milestone.submitted) {
            milestone.submitted = false;
            emit DeclineMilestone(id);
        }
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

    //--------------------------------------------------------------------------------
    // HELPER FUNCTIONS

    function isSameString(string memory first, string memory second)
        private
        pure
        returns (bool)
    {
        return keccak256(bytes(first)) == keccak256(bytes(second));
    }

    /// @dev implies, that the id is valid
    ///@param id : the id of the milestone that should be compared
    ///@param title : the title data set thats compared
    ///@param startDate : the startDate data set thats compared
    ///@param details : the details data set thats compared
    function hasSameMilestoneContent(
        uint256 id,
        string memory title,
        uint256 startDate,
        string memory details
    ) private view returns (bool) {
        Milestone memory createdMilestone = milestones[id];
        return
            //Title and startdate and details are the same respectively
            isSameString(createdMilestone.title, title) &&
            (createdMilestone.startDate == startDate) &&
            isSameString(createdMilestone.details, details);
    }
}
