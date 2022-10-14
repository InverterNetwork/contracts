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

    //----------------------------------
    // Access Control Roles

    /// @inheritdoc IMilestoneManager
    bytes32 public constant CONTRIBUTOR_ROLE =
        keccak256("modules.milestonemanager.contributor");

    //----------------------------------
    // Proposal Callback Function Signatures

    string private constant _FUNC_ADD_MILESTONE =
        "__Milestone_addMilestone(string,uint256,string)";

    string private constant _FUNC_UPDATE_MILESTONE_DETAILS =
        "__Milestone_updateMilestoneDetails(uint256,string)";

    string private constant _FUNC_UPDATE_MILESTONE_START_DATE =
        "__Milestone_updateMilestoneStartDate(uint256,uint256)";

    string private constant _FUNC_REMOVE_MILESTONE =
        "__Milestone_removeMilestone(uint256)";

    string private constant _FUNC_SUBMIT_MILESTONE =
        "__Milestone_submitMilestone(uint256)";

    string private constant _FUNC_CONFIRM_MILESTONE =
        "__Milestone_confirmMilestone(uint256)";

    string private constant _FUNC_DECLINE_MILESTONE =
        "__Milestone_declineMilestone(uint256)";

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of all Milestones.
    /// @dev Milestone id => Milestone.
    mapping(uint => Milestone) private _milestones;

    /// @dev The id assigned to the next created Milestone.
    uint private _milestoneIdCounter;

    //--------------------------------------------------------------------------
    // Modifiers

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
        string memory title,
        uint startDate,
        string memory details
    ) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(
                _FUNC_ADD_MILESTONE, title, startDate, details
            ),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_ADD_MILESTONE);
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
            abi.encodeWithSignature(_FUNC_UPDATE_MILESTONE_DETAILS, id, details),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_UPDATE_MILESTONE_DETAILS);
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
                _FUNC_UPDATE_MILESTONE_START_DATE, id, startDate
            ),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(
                _FUNC_UPDATE_MILESTONE_START_DATE
            );
        }
    }

    /// @inheritdoc IMilestoneManager
    function removeMilestone(uint id) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_REMOVE_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_REMOVE_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function submitMilestone(uint id) external onlyContributor {
        bool ok;
        bytes memory returnData;

        _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_SUBMIT_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_SUBMIT_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function confirmMilestone(uint id) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_CONFIRM_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_CONFIRM_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function declineMilestone(uint id) external onlyAuthorized {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_DECLINE_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_DECLINE_MILESTONE);
        }
    }

    //--------------------------------------------------------------------------
    // Proposal Callback Functions

    // @todo mp: addMilestone needs return value id.

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
        uint id = _milestoneIdCounter++;

        Milestone memory m = Milestone({
            startDate: startDate,
            title: title,
            details: details,
            submitted: false,
            completed: false,
            removed: false
        });

        _milestones[id] = m;
        emit NewMilestoneAdded(id, title, startDate, details);
    }

    function __Milestone_updateMilestoneDetails(uint id, string memory details)
        external
        onlyProposal
        validId(id)
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
    ) external onlyProposal validId(id) {
        Milestone storage m = _milestones[id];

        if (!_isRemoveable(m)) {
            revert Module__MilestoneManager__MilestoneNotRemovable();
        }

        if (!m.removed) {
            m.removed = true;
            emit MilestoneRemoved(id);
        }
    }

    function __Milestone_submitMilestone(uint id)
        external
        onlyProposal
        validId(id)
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

    function __Milestone_confirmMilestone(uint id)
        external
        onlyProposal
        validId(id)
    {
        Milestone storage m = _milestones[id];

        if (!_isConfirmable(m)) {
            revert Module__MilestoneManager__MilestoneNotConfirmable();
        }

        if (!m.completed) {
            m.completed = true;

            // @todo mp, felix: add Payment connection

            emit MilestoneConfirmed(id);
        }
    }

    function __Milestone_declineMilestone(
        uint id //@note maybe at why declined
    ) external onlyProposal validId(id) {
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
    function getMilestone(uint id) external view returns (Milestone memory) {
        Milestone memory m = _milestones[id];

        return m;
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    // @todo mp, felix: The checks are probably _not_ sufficient.
    //                  Need to check with specs again.

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
