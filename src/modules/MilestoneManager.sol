// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {Module, ContextUpgradeable} from "src/modules/base/Module.sol";
import {MilestoneManagerViewContract} from
    "src/modules/MilestoneManagerViewContract.sol";
import {
    IPaymentClient,
    PaymentClient,
    IPaymentProcessor
} from "src/modules/mixins/PaymentClient.sol";

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
    MilestoneManagerViewContract
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyContributorOf(uint milestoneId) {
        if (!isContributor(milestoneId, _msgSender())) {
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

    modifier validPosition(uint id) {
        if (_milestones[id] == 0) {
            revert Module__MilestoneManager__InvalidPosition();
        }
        _;
    }

    /// @dev this does not check if id is SENTINEL. This has to be checked seperately via validId()
    modifier validIntermediatePosition(
        uint id,
        uint prevId,
        uint idToPositionAfter
    ) {
        if (
            (id == idToPositionAfter) //Make sure it doesnt move after itself
                || (idToPositionAfter == prevId) //Make sure it doesnt move before itself
                || _milestoneRegistry[id].startTimestamp != 0 //Milestone hasnt started
                || (
                    _milestoneRegistry[_milestones[idToPositionAfter]]
                        .startTimestamp != 0
                ) //If the following milestone already started you cant move or add a new milestone here, because it could never be started
        ) {
            revert Module__MilestoneManager__InvalidIntermediatePosition();
        }
        _;
    }

    modifier validSubmissionData(bytes calldata submissionData) {
        if (submissionData.length == 0) {
            revert Module__MilestoneManage__InvalidSubmissionData();
        }
        _;
    }

    modifier validId(uint milestoneId) {
        if (!isExistingMilestoneId(milestoneId)) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }
        _;
    }

    modifier validContributors(Contributor[] calldata contribs) {
        uint contribLength = contribs.length;
        uint salaryPctSum;

        // Fail if contributors list is empty.
        if (contribLength == 0 || contribLength > MAXIMUM_CONTRIBUTORS) {
            revert Module__MilestoneManager__InvalidContributorAmount();
        }

        for (uint i; i < contribLength; ++i) {
            address contributorAddr = contribs[i].addr;
            uint contributorSalary = contribs[i].salary;

            // check the address is valid
            if (
                contributorAddr == address(0)
                    || contributorAddr == address(this)
                    || contributorAddr == address(proposal())
            ) {
                revert Module__MilestoneManager__InvalidContributorAddress();
            }

            // check the address is unique
            for (uint j = i + 1; j < contribLength; ++j) {
                if (contribs[j].addr == contributorAddr) {
                    revert Module__MilestoneManager__DuplicateContributorAddress(
                    );
                }
            }

            // check the salary (as budget percentage) is valid
            if (contributorSalary == 0 || contributorSalary > SALARY_PRECISION)
            {
                revert Module__MilestoneManager__InvalidContributorSalary();
            }

            salaryPctSum += contributorSalary;
        }

        //check salary percentages add up to total
        if (salaryPctSum != SALARY_PRECISION) {
            revert Module__MilestoneManager__InvalidSalarySum();
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
    // Initialization

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);

        // Set up empty list of milestones.
        _milestones[_SENTINEL] = _SENTINEL;
        _last = _SENTINEL;

        // Set _activeMilestone to sentinel as otherwise the 0th milestone would
        // be interpreted as active.
        _activeMilestone = _SENTINEL;
        _milestoneUpdateTimelock = 3 days;

        (SALARY_PRECISION, FEE_PCT, FEE_TREASURY) =
            abi.decode(configdata, (uint, uint, address));

        if (FEE_PCT >= SALARY_PRECISION) {
            revert Module__MilestoneManager__FeeOverHundredPercent();
        }
    }

    //--------------------------------------------------------------------------
    // Milestone API Functions

    /// @inheritdoc IMilestoneManager
    function addMilestone(
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external onlyAuthorizedOrManager returns (uint) {
        _validateMilestoneDetails(duration, budget, contributors, details);

        return _addMilestone(duration, budget, contributors, details);
    }

    /// @inheritdoc IMilestoneManager
    function stopMilestone(uint prevId, uint id)
        external
        onlyAuthorizedOrManager
        validId(id)
        onlyConsecutiveMilestones(prevId, id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Only stoppable if milestone currently active.
        // revert if not started yet or finished already
        if (
            m.startTimestamp == 0
                || block.timestamp > m.startTimestamp + m.duration
        ) {
            revert Module__MilestoneManager__MilestoneNotActive();
        }

        //Move ActiveId To Previous Id
        _activeMilestone = prevId;

        // Remove Current id from _milestones list
        _milestones[prevId] = _milestones[id];
        delete _milestones[id];
        _milestoneCounter--;

        // In case last element was removed, update _last to its previous
        // element.
        if (id == _last) {
            _last = prevId;
        }

        // stop all currently running payments
        __Module_proposal.paymentProcessor().cancelRunningPayments(
            IPaymentClient(address(this))
        );

        emit MilestoneStopped(id);
    }

    /// @inheritdoc IMilestoneManager
    function removeMilestone(uint prevId, uint id)
        external
        onlyAuthorizedOrManager
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
    function startNextMilestone() external onlyAuthorizedOrManager {
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

        IMilestoneManager.Contributor[] memory contribCache = m.contributors;

        if (m.budget != 0) {
            //substract the fee from the budget and send it to treasury
            uint feePayout = ((m.budget / SALARY_PRECISION) * FEE_PCT);

            m.budget -= feePayout;

            _ensureTokenBalance(feePayout);
            proposal().token().safeTransfer(FEE_TREASURY, feePayout);

            // Create payment order for each contributor of the new  milestone.
            uint len = contribCache.length;
            if (contribCache.length == 1) {
                // Calculate the payout amount.
                uint contributorPayout =
                    (m.budget / SALARY_PRECISION) * contribCache[0].salary;

                // Note that the payout SHOULD be fulfilled before the end of the milestone's duration.
                _addPaymentOrder(
                    contribCache[0].addr,
                    contributorPayout,
                    block.timestamp + m.duration
                );
            }
            if (contribCache.length > 1) {
                // memory arrays used as parameters to _addPaymentOrders
                address[] memory recipients = new address[](len);
                uint[] memory amounts = new uint[](len);
                uint[] memory dueTos = new uint[](len);
                for (uint i; i < len; ++i) {
                    // Calculate the contributor payout and add it to contributorPayouts array
                    uint contributorPayout =
                        (m.budget / SALARY_PRECISION) * contribCache[i].salary;
                    amounts[i] = contributorPayout;

                    // Save contributor addresses and dueTos
                    recipients[i] = contribCache[i].addr;
                    dueTos[i] = block.timestamp + m.duration;
                }

                _addPaymentOrders(recipients, amounts, dueTos);
            }
        }

        __Module_proposal.paymentProcessor().processPayments(
            IPaymentClient(address(this))
        );

        emit MilestoneStarted(_last);
    }

    /// @inheritdoc IMilestoneManager
    function updateMilestone(
        uint id,
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external onlyAuthorizedOrManager validId(id) {
        _validateMilestoneDetails(duration, budget, contributors, details);

        Milestone storage m = _milestoneRegistry[id];

        // Not updateable if milestone started already.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotUpdateable();
        }

        bool changed;

        if (m.duration != duration) {
            m.duration = duration;
            changed = true;
        }

        if (m.budget != budget) {
            m.budget = budget;
            changed = true;
        }

        if (
            keccak256(abi.encodePacked(m.details))
                != keccak256(abi.encodePacked(details))
        ) {
            m.details = details;
            changed = true;
        }

        if (hashContributors(m.contributors) != hashContributors(contributors))
        {
            delete m.contributors;
            uint len = contributors.length;
            for (uint i; i < len; ++i) {
                m.contributors.push(contributors[i]);
            }
            changed = true;
        }

        if (changed) {
            m.lastUpdatedTimestamp = block.timestamp;
            emit MilestoneUpdated(id, duration, budget, contributors, details);
        }
    }

    /// @inheritdoc IMilestoneManager
    function moveMilestoneInList(uint id, uint prevId, uint idToPositionAfter)
        external
        onlyAuthorizedOrManager
        validId(id)
        validPosition(prevId)
        validPosition(idToPositionAfter)
        validIntermediatePosition(id, prevId, idToPositionAfter)
        onlyConsecutiveMilestones(prevId, id)
    {
        //Remove current milestone id from list
        uint nextIdInLine = _milestones[id];
        _milestones[prevId] = nextIdInLine;

        //Re-Add Milestone in list:

        //Get the milestone Id that should come after the milestone with idToPositionAfter
        nextIdInLine = _milestones[idToPositionAfter];

        // Add milestone's id inbetween the targeted milestone id (idToPositionAfter) and the originally following id (nextIdInLine)
        _milestones[idToPositionAfter] = id;
        _milestones[id] = nextIdInLine;

        //If _last doesnt point towards Sentinel
        if (_milestones[_last] != _SENTINEL) {
            //either id moved to last position
            if (_milestones[id] == _SENTINEL) {
                _last = id;
            }
            //or id moved away from last position
            else {
                _last = prevId;
            }
        }
    }

    /// @inheritdoc IMilestoneManager
    function submitMilestone(uint milestoneId, bytes calldata submissionData)
        external
        onlyContributorOf(milestoneId)
        validId(milestoneId)
        validSubmissionData(submissionData)
    {
        Milestone storage m = _milestoneRegistry[milestoneId];

        // Not submitable if milestone not started yet or already completed.
        if (m.startTimestamp == 0 || m.completed) {
            revert Module__MilestoneManager__MilestoneNotSubmitable();
        }

        if (m.submissionData.length == 0) {
            m.submissionData = submissionData;
            emit MilestoneSubmitted(milestoneId, submissionData);
        }
    }

    /// @inheritdoc IMilestoneManager
    function completeMilestone(uint milestoneId)
        external
        onlyAuthorizedOrManager
        validId(milestoneId)
    {
        Milestone storage m = _milestoneRegistry[milestoneId];

        // Not confirmable if milestone not submitted yet.
        if (m.submissionData.length == 0) {
            revert Module__MilestoneManager__MilestoneNotCompleteable();
        }

        if (!m.completed) {
            m.completed = true;
            emit MilestoneCompleted(milestoneId);
        }
    }

    /// @inheritdoc IMilestoneManager
    function declineMilestone(uint milestoneId)
        external
        onlyAuthorizedOrManager
        validId(milestoneId)
    {
        Milestone storage m = _milestoneRegistry[milestoneId];

        // Not declineable if milestone not submitted yet or already completed.
        if (m.submissionData.length == 0 || m.completed) {
            revert Module__MilestoneManager__MilestoneNotDeclineable();
        }

        // Declining a milestone removes the submitionData and therefore marks it as not submitted again.
        m.submissionData = "";
        emit MilestoneDeclined(milestoneId);
    }

    function changeTreasuryAddress(address to) external {
        if (_msgSender() != FEE_TREASURY) {
            revert Module__MilestoneManager__OnlyCallableByTreasury();
        }
        FEE_TREASURY = to;
    }

    //--------------------------------------------------------------------------
    // Internal Function Implementations

    /// @notice Adds a milestone instance to the list of current milestones
    /// @dev sub-function created to circumvent stackTooDeep errors, assumes parameters have been validated before
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param contributors The contributor information for the milestone
    /// @param details The milestone's details.
    /// @return _id The newly added milestone's id.
    function _addMilestone(
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    ) internal returns (uint _id) {
        // Note ids start at 1.
        uint milestoneId = ++_nextId;

        // Increase counter and cache result.
        ++_milestoneCounter;

        // Add milestone's id to end of list.
        _milestones[_last] = milestoneId;
        _milestones[milestoneId] = _SENTINEL;
        _last = milestoneId;

        // Add milestone instance to registry.
        _milestoneRegistry[milestoneId].duration = duration;
        _milestoneRegistry[milestoneId].budget = budget;

        uint len = contributors.length;
        for (uint i; i < len; ++i) {
            _milestoneRegistry[milestoneId].contributors.push(contributors[i]);
        }

        _milestoneRegistry[milestoneId].details = details;
        _milestoneRegistry[milestoneId].lastUpdatedTimestamp = block.timestamp;

        emit MilestoneAdded(
            milestoneId, duration, budget, contributors, details
        );

        return milestoneId;
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    /// @notice Internal validation function for all milestone details
    /// @dev Only used as a vehicle for all modifiers, the function itself just returns true
    /// @dev Reverts if an argument invalid.
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param contributors The contributor information for the milestone
    /// @param details The milestone's details.
    function _validateMilestoneDetails(
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    )
        internal
        view
        validDuration(duration)
        validBudget(budget)
        validContributors(contributors)
    {}

    /// @notice Creates a hash of a given set of ontributors for easy comparison
    /// @param contributors The set of contributors to hash.
    /// @return The hashed contributor information.
    function hashContributors(Contributor[] memory contributors)
        internal
        pure
        returns (bytes32)
    {
        uint len = contributors.length;

        address[] memory addrCache = new address[](len);
        uint[] memory salaryCache = new uint[](len);
        bytes32[] memory dataCache = new bytes32[](len);

        for (uint i; i < len; ++i) {
            addrCache[i] = contributors[i].addr;
            salaryCache[i] = contributors[i].salary;
            dataCache[i] = contributors[i].data;
        }

        return keccak256(abi.encodePacked(addrCache, salaryCache, dataCache));
    }

    function updateMilestoneUpdateTimelock(uint _newTimelock)
        external
        onlyAuthorized
    {
        _milestoneUpdateTimelock = _newTimelock;
        emit MilestoneUpdateTimelockUpdated(_milestoneUpdateTimelock);
    }

    //--------------------------------------------------------------------------
    // {PaymentClient} Function Implementations

    function _ensureTokenBalance(uint amount)
        internal
        override(PaymentClient)
    {
        uint balance = __Module_proposal.token().balanceOf(address(this));

        if (balance < amount) {
            // Trigger callback from proposal to transfer tokens
            // to address(this).
            bool ok;
            (ok, /*returnData*/ ) = __Module_proposal.executeTxFromModule(
                address(__Module_proposal.token()),
                abi.encodeWithSignature(
                    "transfer(address,uint256)", address(this), amount - balance
                )
            );

            if (!ok) {
                revert Module__PaymentClient__TokenTransferFailed();
            }
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override(PaymentClient)
    {
        IERC20 token = __Module_proposal.token();
        uint allowance = token.allowance(address(this), address(spender));

        if (allowance < amount) {
            token.safeIncreaseAllowance(address(spender), amount - allowance);
        }
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor who)
        internal
        view
        override(PaymentClient)
        returns (bool)
    {
        return __Module_proposal.paymentProcessor() == who;
    }
}
