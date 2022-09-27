pragma solidity ^0.8.13;

// Internal Dependencies
import {Types} from "src/common/Types.sol";

import {Module} from "./base/Module.sol";

import {IProposal} from "src/interfaces/IProposal.sol";

error InplausibleIdInArray();

contract MilestoneModule is Module {
    struct Milestone {
        uint256 identifier; //Could go with a name/hash
        uint256 startDate;
        uint256 duration; //Does the duration serve a purpose or is it just informational?
        string details; //Could go instead with an ipfs hash or a link
        bool submitted;
        bool completed;
    }

    Milestone[] public milestones;

    event NewMilestone(
        uint256 identifier,
        uint256 startDate,
        uint256 duration,
        string details
    );

    event ChangeMilestone(
        uint256 identifier,
        uint256 startDate,
        uint256 duration,
        string details
    );

    event RemoveMilestone(uint256 identifier);
    event SubmitMilestone(uint256 identifier);
    event ConfirmMilestone(uint256 identifier);
    event DeclineMilestone(uint256 identifier);

    modifier ownerAccess() {
        //@todo Governance Link here
        _;
    }

    modifier contributorAccess() {
        //@todo Governance Link here
        _;
    }

    modifier plausableIdInArray(uint256 idInArray) {
        if (idInArray >= milestones.length) {
            revert InplausibleIdInArray();
        }
        _;
    }

    constructor() {}

    function initialize(IProposal proposal) external {//@note Removed initializer because underlying __Module_init() is initializer
        __Module_init(proposal);
        //@todo set GovernanceModule
        //@todo Set PayableModule
    }

    function __Milestone_addMilestone(
        uint256 identifier,
        uint256 startDate, //Possible Startdate now
        uint256 duration,
        string memory details
    ) external onlyProposal returns (uint256 id) {
        //@todo Require correct inputs
        milestones.push(
            Milestone(identifier, startDate, duration, details, false, false)
        );
        emit NewMilestone(identifier, startDate, duration, details);
        return milestones.length - 1;
    }

    function addMilestone(
        uint256 identifier,
        uint256 startDate, //Possible Startdate now
        uint256 duration,
        string memory details
    ) external ownerAccess returns (uint256 id) {
        _triggerProposalCallback(
            abi.encodeWithSignature( //@todo //@note return value?
                "__Milestone_addMilestone(uint256,uint256,uint256,string)",
                identifier,
                startDate,
                duration,
                details
            ),
            Types.Operation.Call
        );
    }

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

    function changeMilestone(
        uint256 idInArray,
        uint256 startDate,
        uint256 duration,
        string memory details
    ) external ownerAccess plausableIdInArray(idInArray) {
        _triggerProposalCallback(
            abi.encodeWithSignature( //@todo @note is this correct? @note string correct encoded?
                "__Milestone_changeMilestone(uint256,uint256,uint256,string)",
                idInArray,
                startDate,
                duration,
                details
            ),
            Types.Operation.Call
        );
    }

    //Unordered removal of the milestone
    //There might be a point made to increase the level of interaction required to remove a milestone
    function __Milestone_removeMilestone(uint256 idInArray)
        external
        onlyProposal
    {
        //@todo Require correct inputs
        uint256 IdToRemove = milestones[idInArray].identifier;
        milestones[idInArray] = milestones[milestones.length - 1];
        milestones.pop();

        emit RemoveMilestone(IdToRemove);
    }

    function removeMilestone(uint256 idInArray)
        external
        ownerAccess
        plausableIdInArray(idInArray)
    {
        _triggerProposalCallback(
            abi.encodeWithSignature( //@todo @note is this correct?
                "__Milestone_removeMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }

    function __Milestone_submitMilestone(uint256 idInArray)
        external
        onlyProposal
    {
        //@todo Require correct inputs
        //@todo Require Milestone not already submitted or confirmed
        Milestone storage milestone = milestones[idInArray];
        milestone.submitted = true;

        emit SubmitMilestone(milestone.identifier);
    }

    function submitMilestone(uint256 idInArray)
        external
        contributorAccess
        plausableIdInArray(idInArray)
    {
        _triggerProposalCallback(
            abi.encodeWithSignature( //@todo @note is this correct?
                "__Milestone_submitMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }

    function __Milestone_confirmMilestone(uint256 idInArray)
        external
        onlyProposal
    {
        //@todo Require Milestone Submitted & not confirmed
        Milestone storage milestone = milestones[idInArray];
        milestone.completed = true;

        //milestone.submitted = true; //@note Change this to false?

        //@todo add Payment

        emit ConfirmMilestone(milestone.identifier);
    }

    function confirmMilestone(uint256 idInArray)
        external
        ownerAccess
        plausableIdInArray(idInArray)
    {
        _triggerProposalCallback(
            abi.encodeWithSignature( //@todo @note is this correct?
                "__Milestone_confirmMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }

    function __Milestone_declineMilestone(uint256 idInArray)
        external
        onlyProposal
    {
        //@todo Require Milestone Submitted & not confirmed
        Milestone storage milestone = milestones[idInArray];
        milestone.submitted = false;

        emit DeclineMilestone(milestone.identifier);
    }

    function declineMilestone(uint256 idInArray)
        external
        ownerAccess
        plausableIdInArray(idInArray)
    {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_declineMilestone(uint256)",
                idInArray
            ),
            Types.Operation.Call
        );
    }
}
