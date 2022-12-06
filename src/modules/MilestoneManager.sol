// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {ERC1155Upgradeable} from "@oz-up/token/ERC1155/ERC1155Upgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module, ContextUpgradeable} from "src/modules/base/Module.sol";
import {
    PaymentClient,
    IPaymentProcessor
} from "src/modules/mixins/PaymentClient.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Internal Interfaces
import {IMilestoneManager} from "src/modules/IMilestoneManager.sol";
import {IProposal} from "src/proposal/IProposal.sol";

/**
 * @title MilestoneManager
 *
 * @dev Module to manage milestones for a proposal.
 *
 *      A milestone can exists in 4 different states:
 *        - added
 *              The milestone got added to the contract.
 *        - active
 *              When a milestone is started, it initias payment orders to pay
 *              the proposal's contributors.
 *              A milestone is active, until either its duration is over or it's
 *              marked as completed.
 *        - submitted
 *              A proposal contributor marks a milestone as submitted by
 *              submitting non-empty data that can be interpreted and evaluated
 *              by off-chain systems.
 *        - completed
 *              After a milestone was submitted, it can be marked as completed.
 *              This marks the end of the milestone.
 *
 * @author byterocket
 */
contract MilestoneManager is
    IMilestoneManager,
    Module,
    PaymentClient,
    ERC1155Upgradeable
{
    using LibString for string;
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyContributor() {
        if (!__Module_proposal.isContributor(_msgSender())) {
            revert Module__MilestoneManager__OnlyCallableByContributor();
        }
        _;
    }

    modifier validDuration(uint duration) {
        if (duration == 0) {
            revert Module__MilestoneManager__InvalidDuration();
        }
        _;
    }

    modifier validBudget(uint budget) {
        // Note that there are no constraints for a budget (Issue #97).
        _;
    }

    modifier validTitle(string memory title_) {
        if (title_.isEmpty()) {
            revert Module__MilestoneManager__InvalidTitle();
        }
        _;
    }

    modifier validDetails(string memory details) {
        if (details.isEmpty()) {
            revert Module__MilestoneManager__InvalidDetails();
        }
        _;
    }

    modifier validSubmissionData(bytes calldata submissionData) {
        if (submissionData.length == 0) {
            revert Module__MilestoneManage__InvalidSubmissionData();
        }
        _;
    }

    modifier validId(uint id) {
        if (!isExistingMilestoneId(id)) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }
        _;
    }

    modifier onlyConsecutiveMilestones(uint prevId, uint id) {
        if (_milestones[prevId] != id) {
            revert Module__MilestoneManager__MilestonesNotConsecutive();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the beginning of the list.
    /// @dev Unrealistic to have that many milestones.
    uint internal constant _SENTINEL = type(uint).max;

    /// @dev Marks the last element of the list.
    /// @dev Always links back to the _SENTINEL.
    uint internal _last;

    // @audit Should be a module argument.
    string internal constant _URI = "";

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Registry mapping milestone id's to Milestone structs.
    mapping(uint => Milestone) private _milestoneRegistry;

    /// @dev List of milestone id's.
    mapping(uint => uint) private _milestones;

    /// @dev Counter for number of milestone id's in the _milestones list.
    uint private _milestoneCounter;

    /// @dev The current active milestone's id.
    /// @dev Uses _SENTINEL to indicate no current active milestone.
    uint private _activeMilestone;

    /// @dev Mapping of milestone id's to their amount of funding.
    ///
    /// @custom:invariant Equals the sum of all ERC-1155 id balances.
    mapping(uint => uint) private _fundsPerMilestone;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override (Module) initializer {
        // Initialize upstream contracts.
        __Module_init(proposal_, metadata);
        __ERC1155_init(_URI);

        // Set up empty list of milestones.
        _milestones[_SENTINEL] = _SENTINEL;
        _last = _SENTINEL;

        // Set _activeMilestone to sentinel as otherwise the 0th milestone would
        // be interpreted as active.
        _activeMilestone = _SENTINEL;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IMilestoneManager
    function getMilestoneInformation(uint id)
        public
        view
        returns (Milestone memory)
    {
        if (!isExistingMilestoneId(id)) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }

        return _milestoneRegistry[id];
    }

    /// @inheritdoc IMilestoneManager
    function listMilestoneIds() public view returns (uint[] memory) {
        uint[] memory result = new uint256[](_milestoneCounter);

        // Populate result array.
        uint index = 0;
        uint elem = _milestones[_SENTINEL];
        while (elem != _SENTINEL) {
            result[index] = elem;
            elem = _milestones[elem];
            index++;
        }

        return result;
    }

    /// @inheritdoc IMilestoneManager
    function getActiveMilestoneId() public view returns (uint id) {
        if (!hasActiveMilestone()) {
            revert Module__MilestoneManager__NoActiveMilestone();
        }

        return _activeMilestone;
    }

    /// @inheritdoc IMilestoneManager
    function hasActiveMilestone() public view returns (bool) {
        if (!isExistingMilestoneId(_activeMilestone)) {
            return false;
        }

        Milestone storage m = _milestoneRegistry[_activeMilestone];

        // Milestone active if not completed and already started but duration
        // not yet over.
        uint startTimestamp = m.startTimestamp;
        return !m.completed && startTimestamp != 0
            && startTimestamp + m.duration >= block.timestamp;
    }

    /// @inheritdoc IMilestoneManager
    function isNextMilestoneActivatable() public view returns (bool) {
        // Return false if next milestone does not exist.
        uint next = _milestones[_activeMilestone];
        if (!isExistingMilestoneId(next)) {
            return false;
        }

        // Return true if current active milestone does not exist.
        if (!isExistingMilestoneId(_activeMilestone)) {
            return true;
        }

        Milestone storage m = _milestoneRegistry[_activeMilestone];

        // Milestone is activatable if current milestone started and its
        // duration exceeded.
        return m.startTimestamp + m.duration < block.timestamp;
    }

    /// @inheritdoc IMilestoneManager
    function isExistingMilestoneId(uint id) public view returns (bool) {
        return id != _SENTINEL && _milestones[id] != 0;
    }

    /// @inheritdoc IMilestoneManager
    function getPreviousMilestoneId(uint id)
        external
        view
        validId(id)
        returns (uint prevId)
    {
        uint[] memory milestoneIds = listMilestoneIds();

        uint len = milestoneIds.length;
        for (uint i; i < len; i++) {
            if (milestoneIds[i] == id) {
                return i != 0 ? milestoneIds[i - 1] : _SENTINEL;
            }
        }
    }

    //--------------------------------------------------------------------------
    // Milestone API Functions

    /// @inheritdoc IMilestoneManager
    function addMilestone(
        uint duration,
        uint budget,
        string memory title_,
        string memory details
    )
        external
        onlyAuthorizedOrOwner
        validDuration(duration)
        validBudget(budget)
        validTitle(title_)
        validDetails(details)
        returns (uint)
    {
        // Increase counter and cache result.
        // Note that ids therefore start at 1.
        uint id = ++_milestoneCounter;

        // Add milestone's id to end of list.
        _milestones[_last] = id;
        _milestones[id] = _SENTINEL;
        _last = id;

        // Add milestone instance to registry.
        _milestoneRegistry[id] = Milestone({
            duration: duration,
            budget: budget,
            title: title_,
            details: details,
            startTimestamp: 0,
            submissionData: "",
            completed: false
        });

        emit MilestoneAdded(id, duration, budget, title_, details);

        return id;
    }

    /// @inheritdoc IMilestoneManager
    function removeMilestone(uint prevId, uint id)
        external
        onlyAuthorizedOrOwner
        validId(id)
        onlyConsecutiveMilestones(prevId, id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not removeable if milestone started already.
        // Note that this also ensures completed milestones are non-removable.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotRemovable();
        }

        // Remove milestone instance from registry.
        delete _milestoneRegistry[id];

        // Remove milestone's id from list and decrease counter.
        _milestones[prevId] = _milestones[id];
        delete _milestones[id];
        _milestoneCounter--;

        // In case last element was removed, update _last to its previous
        // element.
        if (id == _last) {
            _last = prevId;
        }

        emit MilestoneRemoved(id);
    }

    /// @inheritdoc IMilestoneManager
    function startNextMilestone() external onlyAuthorizedOrOwner {
        if (!isNextMilestoneActivatable()) {
            revert Module__MilestoneManager__MilestoneNotActivateable();
        }

        // Get next milestone's id and update _activeMilestone.
        uint next = _milestones[_activeMilestone];
        _activeMilestone = next;

        // Receive pointer to next milestone instance.
        Milestone storage m = _milestoneRegistry[next];

        // Mark milestone as started, i.e. set its startTimestamp.
        m.startTimestamp = block.timestamp;

        // Fetch current contributors from proposal.
        address[] memory contributors = __Module_proposal.listContributors();
        uint contributorsLen = contributors.length;

        // Fail if contributors list is empty.
        if (contributorsLen == 0) {
            revert Module__MilestoneManager__NoContributors();
        }

        if (m.budget != 0) {
            // Calculate the payout amount for each contributor.
            // Note that currently each contributor receives the same amount.
            uint contributorPayout = m.budget / contributorsLen;

            // Add milestone's payout for each contributor as new payment order.
            // Note that the payout SHOULD be fulfilled before the end of the
            // milestone's duration.
            _addIdenticalPaymentOrders(
                contributors, contributorPayout, m.duration
            );
        }
    }

    /// @inheritdoc IMilestoneManager
    function updateMilestone(
        uint id,
        uint duration,
        uint budget,
        string memory details
    )
        external
        onlyAuthorizedOrOwner
        validId(id)
        validDuration(duration)
        validBudget(budget)
        validDetails(details)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not updateable if milestone started already.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotUpdateable();
        }

        if (
            m.duration != duration || m.budget != budget
                || m.details.equals(details)
        ) {
            m.duration = duration;
            m.budget = budget;
            m.details = details;
            emit MilestoneUpdated(id, duration, budget, details);
        }
    }

    /// @inheritdoc IMilestoneManager
    function submitMilestone(uint id, bytes calldata submissionData)
        external
        onlyContributor
        validId(id)
        validSubmissionData(submissionData)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not submitable if milestone not started yet or already completed.
        if (m.startTimestamp == 0 || m.completed) {
            revert Module__MilestoneManager__MilestoneNotSubmitable();
        }

        if (m.submissionData.length == 0) {
            m.submissionData = submissionData;
            emit MilestoneSubmitted(id, submissionData);
        }
    }

    /// @inheritdoc IMilestoneManager
    function completeMilestone(uint id)
        external
        onlyAuthorizedOrOwner
        validId(id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not confirmable if milestone not submitted yet.
        if (m.submissionData.length == 0) {
            revert Module__MilestoneManager__MilestoneNotCompleteable();
        }

        if (!m.completed) {
            m.completed = true;
            emit MilestoneCompleted(id);
        }
    }

    /// @inheritdoc IMilestoneManager
    function declineMilestone(uint id)
        external
        onlyAuthorizedOrOwner
        validId(id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not declineable if milestone not submitted yet or already completed.
        if (m.submissionData.length == 0 || m.completed) {
            revert Module__MilestoneManager__MilestoneNotDeclineable();
        }

        // Declining a milestone removes the submitionData and therefore marks it as not submitted again.
        m.submissionData = "";
        emit MilestoneDeclined(id);
    }

    //--------------------------------------------------------------------------
    // Funding Implementation
    //
    // Funding is managed via a balance for the specific milestone id.
    // For the accounting, the ERC-1155 standard is used with the id being
    // the milestone's id, and the sum of all id's balances the amount of
    // available funds per milestone.

    function deposit(uint id, uint amount)
        external
        validId(id)
        validAmount(amount)
    {
        // Get storage pointer to milestone.
        Milestone storage m = _milestoneRegistry[id];

        // Revert if milestone already started.
        if (m.startTimestamp != 0) {
            revert("Milestone already started");
        }

        // Fetch deposit tokens from caller.
        // Note that the token is assumed to not enable reentrancy. @audit Reasonable?
        __Module_proposal.token().safeTransferFrom(
            msg.sender, address(this), amount
        );

        // Update the total funds available for the milestone.
        _fundsPerMilestone[id] += amount;

        // Mint funding tokens to caller.
        // Note that the _mint function includes a callback into the caller,
        // therefore enabling reentrancy.
        _mint(msg.sender, id, amount, bytes(""));
    }

    function withdraw(uint id, uint amount)
        external
        validId(id)
        validAmount(id)
    {
        // Get storage pointer to milestone.
        Milestone storage m = _milestoneRegistry[id];

        // Revert if milestone started but not completed.
        if (m.startTimestamp != 0 && !m.completed) {
            revert("Milestone active");
        }

        // Burn funding tokens from caller.
        // Note that the _burn function has no callback to the caller.
        _burn(msg.sender, id, amount);

        // Send tokens to caller.
        // Note that the token is assumed to not enable reentrancy. @audit Reasonable?
        __Module_proposal.token().safeTransfer(msg.sender, amount);

        // Update the total funds available for the milestone.
        _fundsPerMilestone[id] -= amount;
    }

    //--------------------------------------------------------------------------
    // {PaymentClient} Function Implementations

    /// @dev Ensures the funding of the current active milestone is at least
    ///      `amount`.
    /// @dev From this point on the tokens are allocated for the payment,
    ///      meaning they can not be withdrawn anymore.
    function _ensureTokenBalance(uint amount)
        internal
        override (PaymentClient)
    {
        // Cache the proposal's token instance.
        IERC20 token = __Module_proposal.token();

        // Get the total funding for this milestone.
        uint funding = _fundsPerMilestone[_activeMilestone];

        // This check should never fail.
        assert(token.balanceOf(address(this)) >= funding);

        // Revert if funding not sufficient.
        if (funding < amount) {
            revert("Not enough funding for milestone");
        }

        // Account `amount` is being allocated, i.e. non-withdrawable, by
        // updating the milestone's available funds.
        _fundsPerMilestone[_activeMilestone] -= amount;
    }

    /// @dev Ensures the token allowance for `spender` is at least `amount`.
    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override (PaymentClient)
    {
        // @audit Use normal approve.
        IERC20 token = __Module_proposal.token();
        uint allowance = token.allowance(address(this), address(spender));

        if (allowance < amount) {
            token.safeIncreaseAllowance(address(spender), amount - allowance);
        }
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor who)
        internal
        view
        override (PaymentClient)
        returns (bool)
    {
        return __Module_proposal.paymentProcessor() == who;
    }
}
