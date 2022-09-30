pragma solidity ^0.8.13;

// Internal Dependencies
import {Types} from "src/common/Types.sol";

import {Module} from "./base/Module.sol";

import {IProposal} from "src/interfaces/IProposal.sol";

///@dev There is no milestone in the milestone array with this id
error InplausibleIdInArray();

///@dev The Milestone is not yet submitted
error MilestoneNotSubmitted();

///@dev The Milestone is already completed
error MilestoneCompleted();

contract MilestoneModule is Module {
    //++++++++++++++++++++++++++++++++++++++++++ STRUCTS ++++++++++++++++++++++++++++++++++++++++++

    // @audit For each user-defined struct field, create an `validXX` modifier,
    //        e.g. `validIdentifier()` and corresponding error type.
    //        Example: https://github.com/byterocket/kolektivo-contracts/blob/main/src/GeoNFT.sol#L69
    struct Milestone {
        uint256 identifier; //@note Could go with a name/hash
        uint256 startDate;
        uint256 duration; //@note Does the duration serve a purpose or is it just informational?
        string details; //@note Could go instead with an ipfs hash or a link
        bool submitted;
        bool completed;
    }

    // Example modifier.
    modifier validDetails(string memory details) {
        if (bytes(details).length != 0) {
            revert Milesonte_InvalidDetails();
        }
        _;
    }

    //++++++++++++++++++++++++++++++++++++++++++ STATE ++++++++++++++++++++++++++++++++++++++++++

    // @audit Why use a list instead of mapping(identifier => Milestone)?
    //        This way the idInArray becomes the effective identifier,
    //        blurring the identifier's semantic meaning.
    Milestone[] public milestones;

    //++++++++++++++++++++++++++++++++++++++++++ EVENTS ++++++++++++++++++++++++++++++++++++++++++

    ///@dev New Milestone was created
    event NewMilestone(
        uint256 identifier,
        uint256 startDate,
        uint256 duration,
        string details
    );

    ///@dev A Milestone was changed in regards of startDate, duration or details
    event ChangeMilestone(
        uint256 identifier,
        uint256 startDate,
        uint256 duration,
        string details
    );

    // @audit Use @notice here.
    ///@dev A Milestone was removed
    event RemoveMilestone(uint256 identifier);

    ///@dev A Milestone was submitted
    event SubmitMilestone(uint256 identifier);

    ///@dev A submitted Milestone was confirmed
    event ConfirmMilestone(uint256 identifier);

    ///@dev A submitted Milestone was declined
    event DeclineMilestone(uint256 identifier);

    //++++++++++++++++++++++++++++++++++++++++++ MODIFIER ++++++++++++++++++++++++++++++++++++++++++

    // @audit Unnecessary. Got `onlyAuthorized` inherited from Module.
    ///@dev Checks via the governance module if msg.sender is owner
    modifier ownerAccess() {
        //@todo Governance Link here
        _;
    }

    // @audit Do we need this according to Spec?
    //        -> Seems so.
    //        Q: Where should the list of contributors be stored?
    //           -> Proposal?
    ///@dev Checks via the governance module if msg.sender is contributor
    modifier contributorAccess() {
        //@todo Governance Link here
        _;
    }

    uint private _milestoneCounter;
    modifier validMilestoneId(uint id) {
        if (id > _milestoneCounter) {
            revert GeoNFT__InvalidTokenId();
        }
        _;
    }

    // @audit Rename to `validId(uint id)` ?
    ///@dev Checks if the given id is available in the milestone array
    ///@param idInArray : id in the milestone array
    modifier plausableIdInArray(uint256 idInArray) {
        if (idInArray >= milestones.length) {
            revert InplausibleIdInArray();
        }
        _;
    }

    ///@dev Checks if the given Milestone is submitted, but not completed
    ///@param idInArray : id in the milestone array
    modifier submittedNotCompleted(uint256 idInArray) {
        if (!milestones[idInArray].submitted) {
            revert MilestoneNotSubmitted();
        }
        if(milestones[idInArray].completed){
            revert MilestoneCompleted();
        }
        _;
    }

    //++++++++++++++++++++++++++++++++++++++++++ CONSTRUCTOR ++++++++++++++++++++++++++++++++++++++++++

    constructor() {}

    // @audit Add initializer. Problem in __Module_init() got fixed.
    ///@notice insitializes the MilestoneModule
    ///@dev Removed initializer because the underlying __Module_init() is initializer
    ///@param proposal : The proposal that should be linked to this module
    function initialize(IProposal proposal) external {
        //@note Removed initializer because underlying __Module_init() is initializer
        __Module_init(proposal);
        //@todo set GovernanceModule
        //@todo Set PayableModule
    }

    //++++++++++++++++++++++++++++++++++++++++++ FUNCTIONS ++++++++++++++++++++++++++++++++++++++++++

    ///@dev Adds a milestone to the milestone array
    ///@param identifier : the identifier for the new milestone
    ///@param startDate : the startDate of the new milestone
    ///@param duration : the duration of the new milestone
    ///@param details : the details of the new milestone
    ///@return id : the id of the new milestone in the milestone array
    function __Milestone_addMilestone(
        uint256 identifier,
        uint256 startDate, //Possible Startdate now
        uint256 duration,
        string memory details
    ) external onlyProposal returns (uint256 id) {
        // @todo felix: Use idCounter or string memory identifier as unique key?

        //@todo Require correct inputs
        milestones.push(
            Milestone(identifier, startDate, duration, details, false, false)
        );
        emit NewMilestone(identifier, startDate, duration, details);
        return milestones.length - 1;
    }

    ///@notice Adds a milestone to the milestone array
    ///@dev Relay Function that routes the function call via the proposal
    ///@param identifier : the identifier for the new milestone
    ///@param startDate : the startDate of the new milestone
    ///@param duration : the duration of the new milestone
    ///@param details : the details of the new milestone
    ///@return id : the id of the new milestone in the milestone array
    function addMilestone(
        uint256 identifier,
        uint256 startDate, //Possible Startdate now
        uint256 duration,
        string memory details
    ) external ownerAccess returns (uint256 id) {
        _triggerProposalCallback(
            abi.encodeWithSignature( //@todo Felix : return value? //@todo Felix : Testing needed
                "__Milestone_addMilestone(uint256,uint256,uint256,string)",
                identifier,
                startDate,
                duration,
                details
            ),
            Types.Operation.Call
        );
    }

    ///@dev Changes a milestone in regards of startDate, duration or details
    ///@param idInArray : id in the milestone array
    ///@param startDate : the new startDate of the given milestone
    ///@param duration : the new duration of the given milestone
    ///@param details : the new details of the given milestone
    function __Milestone_changeMilestone(
        uint256 idInArray,
        uint256 startDate,
        uint256 duration,
        string memory details
    ) external onlyProposal {
        //@todo Require correct inputs
        Milestone memory oldMilestone = milestones[idInArray]; //@note it might be more efficient use storage
        milestones[idInArray] = Milestone(
            oldMilestone.identifier, //Keep old identifier
            startDate,
            duration,
            details,
            oldMilestone.submitted, //Keep submitted Status
            oldMilestone.completed //Keep completed Status
        );
        emit ChangeMilestone(
            oldMilestone.identifier,
            startDate,
            duration,
            details
        );
    }

    ///@notice Changes a milestone in regards of startDate, duration or details
    ///@dev Relay Function that routes the function call via the proposal
    ///@param idInArray : id in the milestone array
    ///@param startDate : the new startDate of the given milestone
    ///@param duration : the new duration of the given milestone
    ///@param details : the new details of the given milestone
    function changeMilestone(
        uint256 idInArray,
        uint256 startDate,
        uint256 duration,
        string memory details
    ) external ownerAccess plausableIdInArray(idInArray) {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_changeMilestone(uint256,uint256,uint256,string)",
                idInArray,
                startDate,
                duration,
                details
            ),
            Types.Operation.Call
        );
    }

    function changeMilestoneDuration(uint id, uint duration) {
        Milestone memory milestone = milestones[id];

        if (milestone.duration != duration) {
            milestone.duration = duration;
            // emit Event
        }
    }

    ///@dev Unordered removal of the milestone from the milestone array
    ///@param idInArray : id in the milestone array
    function __Milestone_removeMilestone(
        uint256 idInArray //@note There might be a point made to increase the level of interaction required to remove a milestone
    ) external onlyProposal plausableIdInArray(idInArray) {
        uint256 IdToRemove = milestones[idInArray].identifier;
        milestones[idInArray] = milestones[milestones.length - 1];
        milestones.pop();

        emit RemoveMilestone(IdToRemove);
    }

    ///@notice Unordered removal of the milestone from the milestone array
    ///@dev Relay Function that routes the function call via the proposal
    ///@param idInArray : id in the milestone array
    function removeMilestone(uint256 idInArray) external ownerAccess {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_removeMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }

    // In a different contract:
    try submitMilestone(10) {
        // if not revert: Got submitted
        // Don't care
    } catch {
        // if revert: No problem
        // Don't care
    }
    // ... continue wirth normal code

    // Programmer submitMilestone:
    // 1: I want to change the milestone submit field to True.
    // 2: I want the milestone submit field to BE True.

    ///@dev Submit a milestone
    ///@param idInArray : id in the milestone array
    function __Milestone_submitMilestone(uint256 idInArray)
        external
        onlyProposal
        plausableIdInArray(idInArray)
        // @audit Function should be idempotent!
        // HTTP: GET, POST, DELETE, ADD
        //            ^^^^  ^^^^^^  XXX->Id
        submittedNotCompleted(idInArray)
    {
        Milestone storage milestone = milestones[idInArray];

        if (!milestone.submitted) {
            milestone.submitted = true;
            emit SubmitMilestone(milestone.identifier);
        }
    }

    ///@notice Submit a milestone
    ///@dev Relay Function that routes the function call via the proposal
    ///@param idInArray : id in the milestone array
    function submitMilestone(uint256 idInArray) external contributorAccess {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_submitMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }

    ///@dev Confirms a submitted milestone
    ///@param idInArray : id in the milestone array
    function __Milestone_confirmMilestone(uint256 idInArray)
        external
        onlyProposal
        plausableIdInArray(idInArray)
        submittedNotCompleted(idInArray)
    {
        Milestone storage milestone = milestones[idInArray];
        milestone.completed = true;

        //milestone.submitted = true; //@note Change this to false?

        //@note Maybe move the milestone to a seperate array as mark of completion?
        //@todo add Payment

        // @audit Only emit event when state actually mutated.
        emit ConfirmMilestone(milestone.identifier);
    }

    ///@notice Confirms a submitted milestone
    ///@dev Relay Function that routes the function call via the proposal
    ///@param idInArray : id in the milestone array
    function confirmMilestone(uint256 idInArray) external ownerAccess {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_confirmMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }

    ///@dev Declines a submitted milestone
    ///@param idInArray : id in the milestone array
    function __Milestone_declineMilestone(uint256 idInArray)
        external
        onlyProposal
        plausableIdInArray(idInArray)
        submittedNotCompleted(idInArray)

    {
        Milestone storage milestone = milestones[idInArray];
        milestone.submitted = false;

        // @audit Only emit event when state actually mutated.
        emit DeclineMilestone(milestone.identifier);
    }

    ///@notice Declines a submitted milestone
    ///@dev Relay Function that routes the function call via the proposal
    ///@param idInArray : id in the milestone array
    function declineMilestone(uint256 idInArray) external ownerAccess {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_declineMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }
}
