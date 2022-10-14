// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

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
    using LibString for string;

    //--------------------------------------------------------------------------
    // Constants

    // @todo mp: Refactorings
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

    string private constant FUNC_UPDATE_MILESTONE_DETAILS =
        "__Milestone_updateMilestoneDetails(uint256,string)";

    string private constant FUNC_UPDATE_MILESTONE_START_DATE =
        "__Milestone_updateMilestoneStartDate(uint256,uint256)";

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
        if (title.isEmpty()) {
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
        if (details.isEmpty()) {
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

    /// @inheritdoc IMilestoneManager
    function updateMilestoneDetails(uint id, string memory details)
        external
        onlyAuthorized
    {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(FUNC_UPDATE_MILESTONE_DETAILS, id, details),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(FUNC_UPDATE_MILESTONE_DETAILS);
        }
    }

    /// @inheritdoc IMilestoneManager
    function updateMilestoneStartDate(uint id, uint startDate)
        external
        onlyAuthorized
    {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(
                FUNC_UPDATE_MILESTONE_START_DATE, id, startDate
            ),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(
                FUNC_UPDATE_MILESTONE_START_DATE
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

    function __Milestone_addMilestone(
        string memory title,
        uint startDate, //@note Possible Startdate now
        string memory details
    )
        external
        onlyProposal
        validTitle(title)
        validStartDate(startDate)
        validDetails(details)
    {
        // Cache current id and increase id counter.
        uint id = _milestoneIdCounter++;

        // Create new milestone instance.
        Milestone memory m = Milestone({
            startDate: startDate,
            title: title,
            details: details,
            submitted: false,
            completed: false,
            removed: false
        });

        // Write new milestone to storage using current id.
        _milestones[id] = m;

        // Notify off-chain services.
        emit NewMilestoneAdded(id, title, startDate, details);
    }

    function __Milestone_updateMilestoneDetails(uint id, string memory details)
        external
        onlyProposal
        validId(id)
        // notRemoved(id) // @todo mp: Creates extra SLOAD :(
        validDetails(details)
    {
        Milestone storage m = _milestones[id];

        if (!_isUpdateable(m)) {
            revert Module__MilestoneManager__NotUpdateable();
        }

        if (!m.details.equals(details)) {
            m.details = details;
            emit MilestoneDetailsUpdated(id, details);
        }
    }

    function __Milestone_updateMilestoneStartDate(uint id, uint startDate)
        external
        onlyProposal
        validId(id)
        // notRemoved(id) @todo mp: See above.
        validStartDate(startDate)
    {
        Milestone storage m = _milestones[id];

        if (!_isUpdateable(m)) {
            revert Module__MilestoneManager__MilestoneNotUpdateable();
        }

        if (m.startDate != startDate) {
            //@todo felix: test idempotence
            m.startDate = startDate;
            emit MilestoneStartDateUpdated(id, startDate);
        }
    }

    function __Milestone_removeMilestone(
        uint id //@note There might be a point made to increase the level of interaction required to remove a milestone
    ) external onlyProposal validId(id) 
    // notCompleted(id) @todo Creates extra SLOAD :(
    {
        Milestone storage m = _milestones[id];

        if (!_isRemoveable(m)) {
            revert Module__MilestoneManager__MilestoneNotRemovable();
        }

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
    // notRemoved(id) @todo Creates extra SLOAD
    {
        Milestone storage m = _milestones[id];

        if (!_isSubmitable(m)) {
            revert Module__MilestoneManager__MilestoneNotSubmitable();
        }

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
    // notRemoved(id)
    // submitted(id)
    {
        Milestone storage m = _milestones[id];

        if (!_isConfirmable(m)) {
            revert Module__MilestoneManager__MilestoneNotConfirmable();
        }

        if (!m.completed) {
            m.completed = true;

            //@todo add Payment connection

            emit MilestoneConfirmed(id);
        }
    }

    ///@dev Declines a submitted milestone
    ///@param id : id in the milestone array
    function __Milestone_declineMilestone(
        uint id //@note maybe at why declined
    ) external onlyProposal validId(id) 
    // notRemoved(id)
    // submitted(id)
    // notCompleted(id)
    {
        Milestone storage m = _milestones[id];

        if (!_isDeclineable(m)) {
            revert Module__MilestoneManager__MilestoneNotDeclineable();
        }

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

    function _isUpdateable(Milestone storage m) internal view returns (bool) {
        // @todo mp: When is updating not allowed anymore?
        // gitbook: If milestone started already, see https://inverter-network.gitbook.io/inverter-network-docs/creating-a-proposal/managing-milestones#editing-milestone.
        bool notStarted = m.startDate <= block.timestamp;

        return notStarted;
    }

    function _isRemoveable(Milestone storage m) internal view returns (bool) {
        bool notCompleted = !m.completed;

        return notCompleted;
    }

    function _isSubmitable(Milestone storage m) internal view returns (bool) {
        bool notStarted = m.startDate <= block.timestamp;
        bool notRemoved = !m.removed;

        return notStarted && notRemoved;
    }

    function _isConfirmable(Milestone storage m) internal view returns (bool) {
        bool notRemoved = !m.removed;
        bool notSubmitted = !m.submitted;

        return notRemoved && notSubmitted;
    }

    function _isDeclineable(Milestone storage m) internal view returns (bool) {
        bool notRemoved = !m.removed;
        bool submitted = m.submitted;
        bool notCompleted = !m.completed;

        return notRemoved && submitted && notCompleted;
    }
}
