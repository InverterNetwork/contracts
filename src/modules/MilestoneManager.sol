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

    // @todo mp: Refactorings
    //          - Events
    //          - Error add contract prefix
    //          - some function names
    //          - some modifier names

    //----------------------------------
    // Access Control Roles

    /// @inheritdoc IMilestoneManager
    bytes32 public constant CONTRIBUTOR_ROLE =
        keccak256("modules.milestonemanager.contributor");

    //----------------------------------
    // Proposal Callback Function Signatures

    string private constant FUNC_ADD_MILESTONE =
        "__Milestone_addMilestone(uint256,string,uint256,string)";

    string private constant FUNC_CHANGE_MILESTONE_DETAILS =
        "__Milestone_changeDetails(uint256,string)";

    string private constant FUNC_CHANGE_MILESTONE_START_DATE =
        "__Milestone_changeStartDate(uint256,uint256)";

    string private constant FUNC_REMOVE_MILESTONE =
        "__Milestone_removeMilestone(uint256)";

    string private constant FUNC_SUBMIT_MILESTONE =
        "__Milestone_submitMilestone(uint256)";

    string private constant FUNC_CONFIRM_MILESTONE =
        "__Milestone_confirmMilestone(uint256)";

    string private constant FUNC_DECLINE_MILESTONE =
        "__Milestone_declineMilestone(uint256)";

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
            revert Module__MilestoneManager__OnlyCallableByContributor();
        }
        _;
    }

    /// @dev Checks if the given title is valid.
    /// @param title Given milestone title.
    modifier validTitle(string memory title) {
        if ((bytes(title)).length == 0) {
            revert Module__MilestoneManager__InvalidTitle();
        }
        _;
    }

    /// @dev Checks if the given startDate is valid.
    /// @param startDate The given startDate of the milestone.
    modifier validStartDate(uint startDate) {
        if (startDate <= block.timestamp) {
            revert Module__MilestoneManager__InvalidStartDate();
        }
        _;
    }

    /// @dev Checks if the given details is valid.
    /// @param details The given details of the milestone.
    modifier validDetails(string memory details) {
        if ((bytes(details)).length == 0) {
            revert Module__MilestoneManager__InvalidDetails();
        }
        _;
    }

    /// @dev Checks if the given id is available in the milestone array.
    /// @param id The id in the milestone array.
    modifier validId(uint id) {
        if (id >= _milestoneIdCounter) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }
        _;
    }

    /// @dev Checks if the given newId is valid.
    /// @param newId ???
    modifier newMilestoneIdAvailable(uint newId) {
        if (newId > _milestoneIdCounter) {
            revert Module__MilestoneManager__NewMilestoneIdNotYetAvailable();
        }
        _;
    }

    ///@dev Checks if the given Milestone is submitted.
    ///@param id The id in the milestone array.
    modifier submitted(uint id) {
        if (!_milestones[id].submitted) {
            revert Module__MilestoneManager__MilestoneNotSubmitted();
        }
        _;
    }

    ///@dev Checks if the given Milestone is not completed.
    ///@param id The id in the milestone array.
    modifier notCompleted(uint id) {
        if (_milestones[id].completed) {
            revert Module__MilestoneManager__MilestoneAlreadyCompleted();
        }
        _;
    }

    ///@dev Checks if the given Milestone is removed.
    ///@param id The id in the milestone array.
    modifier notRemoved(uint id) {
        if (_milestones[id].removed) {
            revert Module__MilestoneManager__MilestoneRemoved();
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

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(
                FUNC_ADD_MILESTONE, newId, title, startDate, details
            ),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(FUNC_ADD_MILESTONE);
        }
    }

    // @todo mp: Rename to changeMilestoneDetails
    /// @inheritdoc IMilestoneManager
    function changeDetails(uint id, string memory details)
        external
        onlyAuthorized
    {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(FUNC_CHANGE_MILESTONE_DETAILS, id, details),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(FUNC_CHANGE_MILESTONE_DETAILS);
        }
    }

    /// @inheritdoc IMilestoneManager
    function changeStartDate(uint id, uint startDate) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(
                FUNC_CHANGE_MILESTONE_START_DATE, id, startDate
            ),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(
                FUNC_CHANGE_MILESTONE_START_DATE
            );
        }
    }

    /// @inheritdoc IMilestoneManager
    function removeMilestone(uint id) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(FUNC_REMOVE_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(FUNC_REMOVE_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function submitMilestone(uint id) external onlyContributor {
        bool ok;
        bytes memory returnData;

        _triggerProposalCallback(
            abi.encodeWithSignature(FUNC_SUBMIT_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(FUNC_SUBMIT_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function confirmMilestone(uint id) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(FUNC_CONFIRM_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(FUNC_CONFIRM_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function declineMilestone(uint id) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(FUNC_DECLINE_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(FUNC_DECLINE_MILESTONE);
        }
    }

    //--------------------------------------------------------------------------
    // Proposal Callback Functions

    // @todo mp: Do this functions need docs? Same docs as the API functions.

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
            // Increase id counter;
            _milestoneIdCounter++;

            // Create new milestone instance.
            _milestones[newId] = Milestone({
                startDate: startDate,
                submitted: false,
                completed: false,
                removed: false,
                title: title,
                details: details
            });
            emit NewMilestoneAdded(newId, title, startDate, details);
        } else {
            //If its not the same Milestone Content give an error message
            if (!(_hasSameMilestoneContent(newId, title, startDate, details))) {
                revert Module__MilestoneManager__MilestoneWithIdAlreadyCreated();
            }
        }
    }

    // @todo mp: Rename change to update

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

        if (!_isEqual(m.details, details)) {
            m.details = details;
            emit MilestoneDetailsUpdated(id, details);
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
            emit MilestoneStartDateUpdated(id, startDate);
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
            emit MilestoneRemoved(id);
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
            emit MilestoneSubmitted(id);
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

            emit MilestoneConfirmed(id);
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
            emit MilestoneDeclined(id);
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

    function _isEqual(string memory first, string memory second)
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

        bool equalTitles = _isEqual(m.title, title);
        bool equalStartDates = m.startDate == startDate;
        bool equalDetails = _isEqual(m.details, details);

        return equalTitles && equalStartDates && equalDetails;
    }
}
