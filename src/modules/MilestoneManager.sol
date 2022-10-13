// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IMilestoneManager} from "src/interfaces/modules/IMilestoneManager.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

/**
 * @title Milestone Module
 *
 * @dev @todo felix: Add contract documentation
 *
 * @author byterocket
 */
contract MilestoneManager is IMilestoneManager, Module {
    //--------------------------------------------------------------------------
    // Constants

    /// @inheritdoc IMilestoneManager
    bytes32 public constant CONTRIBUTOR_ROLE =
        keccak256("modules.milestonemanager.contributor");

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of all Milestones.
    /// @dev Milestone id => Milestone.
    mapping(uint => Milestone) private _milestones;

    /// @dev The id assigned to the next created Milestone.
    uint private _milestoneIdCounter;

    //--------------------------------------------------------------------------
    // MODIFIER

    /// @dev Checks via the governance module if msg.sender is contributor.
    modifier onlyContributor() {
        // @todo mp: Use _msgSender().
        bool isContributor = __Module_proposal.hasRole(
            address(this), CONTRIBUTOR_ROLE, msg.sender
        );
        if (!isContributor) {
            revert OnlyCallableByContributor();
        }
        _;
    }

    /// @dev Checks if the given title is valid.
    /// @param title Given milestone title.
    modifier validTitle(string memory title) {
        if ((bytes(title)).length == 0) {
            revert InvalidTitle();
        }
        _;
    }

    /// @dev Checks if the given startDate is valid.
    /// @param startDate The given startDate of the milestone.
    modifier validStartDate(uint startDate) {
        /* if () {//@note not in past?
         revert InvalidStartDate();
       } */
        _;
    }

    /// @dev Checks if the given details is valid.
    /// @param details The given details of the milestone.
    modifier validDetails(string memory details) {
        if ((bytes(details)).length == 0) {
            revert InvalidDetails();
        }
        _;
    }

    /// @dev Checks if the given id is available in the milestone array.
    /// @param id The id in the milestone array.
    modifier validId(uint id) {
        if (id >= _milestoneIdCounter) {
            revert InvalidMilestoneId();
        }
        _;
    }

    /// @dev Checks if the given newId is valid.
    /// @param newId ???
    modifier newMilestoneIdAvailable(uint newId) {
        if (newId > _milestoneIdCounter) {
            revert NewMilestoneIdNotYetAvailable();
        }
        _;
    }

    ///@dev Checks if the given Milestone is submitted.
    ///@param id The id in the milestone array.
    modifier submitted(uint id) {
        if (!_milestones[id].submitted) {
            revert MilestoneNotSubmitted();
        }
        _;
    }

    ///@dev Checks if the given Milestone is not completed.
    ///@param id The id in the milestone array.
    modifier notCompleted(uint id) {
        if (_milestones[id].completed) {
            revert MilestoneAlreadyCompleted();
        }
        _;
    }

    ///@dev Checks if the given Milestone is removed.
    ///@param id The id in the milestone array.
    modifier notRemoved(uint id) {
        if (_milestones[id].removed) {
            revert MilestoneRemoved();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Initialization

    constructor() {}

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override (Module) initializer {
        __Module_init(proposal_, metadata);

        // @todo felix: Set Payment module.
    }

    //--------------------------------------------------------------------------
    // Access Control Functions

    /// @inheritdoc IMilestoneManager
    function grantContributorRole(address account) public onlyAuthorized {
        __Module_proposal.grantRole(CONTRIBUTOR_ROLE, account);
    }

    /// @inheritdoc IMilestoneManager
    function revokeContributorRole(address account) public onlyAuthorized {
        __Module_proposal.revokeRole(CONTRIBUTOR_ROLE, account);
    }

    //--------------------------------------------------------------------------
    // Milestone API Functions

    /// @inheritdoc IMilestoneManager
    function addMilestone(
        uint newId,
        string memory title,
        uint startDate, //Possible Startdate now
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

    /// @inheritdoc IMilestoneManager
    function changeDetails(uint id, string memory details)
        external
        onlyAuthorized
    {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_changeDetails(uint256,string)", id, details
            ),
            Types.Operation.Call
        );
    }

    /// @inheritdoc IMilestoneManager
    function changeStartDate(uint id, uint startDate) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Milestone_changeStartDate(uint256,uint256)", id, startDate
            ),
            Types.Operation.Call
        );
    }

    /// @inheritdoc IMilestoneManager
    function removeMilestone(uint id) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Milestone_removeMilestone(uint256)", id),
            Types.Operation.Call
        );
    }

    /// @inheritdoc IMilestoneManager
    function submitMilestone(uint id) external onlyContributor {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Milestone_submitMilestone(uint256)", id),
            Types.Operation.Call
        );
    }

    /// @inheritdoc IMilestoneManager
    function confirmMilestone(uint id) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Milestone_confirmMilestone(uint256)", id),
            Types.Operation.Call
        );
    }

    /// @inheritdoc IMilestoneManager
    function declineMilestone(uint id) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Milestone_declineMilestone(uint256)", id),
            Types.Operation.Call
        );
    }

    //--------------------------------------------------------------------------
    // Proposal Callback Functions

    /// @dev Adds milestone to the milestone mapping
    /// @dev
    /// @param newId : the id of the new milestone
    /// @param title : the title for the new milestone
    /// @param startDate : the startDate of the new milestone
    /// @param details : the details of the new milestone
    function __Milestone_addMilestone(
        uint newId,
        string memory title,
        uint startDate, //@note Possible Startdate now
        string memory details
    )
        external
        onlyProposal
        newMilestoneIdAvailable(newId)
        validTitle(title)
        validStartDate(startDate)
        validDetails(details)
    {
        if (newId == _milestoneIdCounter) {
            _milestones[_milestoneIdCounter++] = Milestone({
                startDate: startDate,
                submitted: false,
                completed: false,
                removed: false,
                title: title,
                details: details
            });
            emit NewMilestone(title, startDate, details);
        } else {
            //If its not the same Milestone Content give an error message
            if (!(_hasSameMilestoneContent(newId, title, startDate, details))) {
                revert MilestoneWithIdAlreadyCreated();
            }
        }
    }

    ///@dev Changes a milestone in regards of details
    ///@param id : id in the milestone array
    ///@param details : the new details of the given milestone
    function __Milestone_changeDetails(uint id, string memory details)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        validDetails(details)
    {
        Milestone storage m = _milestones[id];

        if (!_isSameString(m.details, details)) {
            m.details = details;
            emit ChangeDetails(id, details);
        }
    }

    ///@dev Changes a milestone in regards of startDate
    ///@param id : id in the milestone array
    ///@param startDate : the new startDate of the given milestone
    function __Milestone_changeStartDate(uint id, uint startDate)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        validStartDate(startDate)
    {
        Milestone storage m = _milestones[id];

        if (m.startDate != startDate) {
            //@todo test idempotence
            m.startDate = startDate;
            emit ChangeStartDate(id, startDate);
        }
    }

    ///@dev removal of the milestone
    ///@param id : id in the milestone array
    function __Milestone_removeMilestone(
        uint id //@note There might be a point made to increase the level of interaction required to remove a milestone
    ) external onlyProposal validId(id) notCompleted(id) {
        Milestone storage m = _milestones[id];

        if (!m.removed) {
            m.removed = true;
            emit RemoveMilestone(id);
        }
    }

    // Programmer submitMilestone:
    // 1: I want to change the milestone submit field to True.
    // 2: I want the milestone submit field to BE True.

    ///@dev Submit a milestone
    ///@param id : id in the milestone array
    function __Milestone_submitMilestone(uint id)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
    {
        Milestone storage m = _milestones[id];

        if (!m.submitted) {
            m.submitted = true;
            emit SubmitMilestone(id);
        }
    }

    ///@dev Confirms a submitted milestone
    ///@param id : id in the milestone array
    function __Milestone_confirmMilestone(uint id)
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        submitted(id)
    {
        Milestone storage m = _milestones[id];
        if (!m.completed) {
            m.completed = true;

            //@note pay who and how much?
            //@todo add Payment

            emit ConfirmMilestone(id);
        }
    }

    ///@dev Declines a submitted milestone
    ///@param id : id in the milestone array
    function __Milestone_declineMilestone(
        uint id //@note maybe at why declined
    )
        external
        onlyProposal
        validId(id)
        notRemoved(id)
        submitted(id)
        notCompleted(id)
    {
        Milestone storage m = _milestones[id];
        if (m.submitted) {
            m.submitted = false;
            emit DeclineMilestone(id);
        }
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IMilestoneManager
    function milestone(uint id) external view returns (Milestone memory) {
        Milestone memory m = _milestones[id];

        return m;
    }

    /// @inheritdoc IMilestoneManager
    function nextNewMilestoneId() external view returns (uint) {
        return _milestoneIdCounter;
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _isSameString(string memory first, string memory second)
        internal
        pure
        returns (bool)
    {
        if (bytes(first).length != bytes(second).length) {
            return false;
        } else {
            return keccak256(bytes(first)) == keccak256(bytes(second));
        }
    }

    /// @dev implies, that the id is valid
    ///@param id : the id of the milestone that should be compared
    ///@param title : the title data set thats compared
    ///@param startDate : the startDate data set thats compared
    ///@param details : the details data set thats compared
    function _hasSameMilestoneContent(
        uint id,
        string memory title,
        uint startDate,
        string memory details
    ) internal view returns (bool) {
        Milestone memory m = _milestones[id];

        bool equalTitles = _isSameString(m.title, title);
        bool equalStartDates = m.startDate == startDate;
        bool equalDetails = _isSameString(m.details, details);

        return equalTitles && equalStartDates && equalDetails;
    }
}
