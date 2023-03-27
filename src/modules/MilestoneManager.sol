// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module, ContextUpgradeable} from "src/modules/base/Module.sol";
import {
    IPaymentClient,
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
contract MilestoneManager is IMilestoneManager, Module, PaymentClient {
    using LibString for string;
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
            bytes32 contributorData = contribs[i].data;

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
    // Constants

    /// @dev Marks the beginning of the list.
    /// @dev Unrealistic to have that many milestones.
    uint internal constant _SENTINEL = type(uint).max;

    /// @dev Marks the last element of the list.
    /// @dev Always links back to the _SENTINEL.
    uint internal _last;

    /// @dev Marks the maximum amount of contributors per milestone.
    /// @dev Setting a reasonable limit prevents running into 'out of gas' issues with the generated payment order array
    uint internal constant MAXIMUM_CONTRIBUTORS = 50;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Registry mapping milestone ids to Milestone structs.
    mapping(uint => Milestone) private _milestoneRegistry;

    /// @dev List of milestone id's.
    mapping(uint => uint) private _milestones;

    /// @dev Counter for number of milestone id's in the _milestones list.
    uint private _milestoneCounter;

    /// @dev The current active milestone's id.
    /// @dev Uses _SENTINEL to indicate no current active milestone.
    uint private _activeMilestone;

    /// @dev The current minimum time gap between the updating and staring of a milestone
    /// @dev The default value will be 3 days. Can be updated by authorized addresses.
    uint private _milestoneUpdateTimelock;

    /// @dev Marks the precision we will use for the salary percentages. Represents what counts as "100%".
    /// @dev Value is 100_000_000 since it allows for 1$ precision in a 1.000.000$ budget.
    uint internal SALARY_PRECISION;

    /// @dev Defines what part of the Budget gets taken as fee at the start of a Milestone.
    /// @dev defined as a value relative to the SALARY_PRECISION
    uint internal FEE_PCT;

    /// @dev Treasury address to send the fees to.
    address private FEE_TREASURY;

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
        uint index;
        uint elem = _milestones[_SENTINEL];
        while (elem != _SENTINEL) {
            result[index] = elem;
            elem = _milestones[elem];
            index++;
        }

        return result;
    }

    /// @inheritdoc IMilestoneManager
    function getActiveMilestoneId() public view returns (uint milestoneId) {
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

        if (
            block.timestamp - _milestoneRegistry[next].lastUpdatedTimestamp
                < _milestoneUpdateTimelock
        ) {
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
        for (uint i; i < len; ++i) {
            if (milestoneIds[i] == id) {
                return i != 0 ? milestoneIds[i - 1] : _SENTINEL;
            }
        }
    }

    /// @inheritdoc IMilestoneManager
    function isContributor(uint milestoneId, address who)
        public
        view
        returns (bool)
    {
        Contributor[] memory contribs =
            getMilestoneInformation(milestoneId).contributors;

        uint len = contribs.length;
        for (uint i; i < len; ++i) {
            if (contribs[i].addr == who) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IMilestoneManager
    function getSalaryPrecision() public view returns (uint) {
        return SALARY_PRECISION;
    }

    function getFeePct() public view returns (uint) {
        return FEE_PCT;
    }

    /// @inheritdoc IMilestoneManager
    function getMaximumContributors() public pure returns (uint) {
        return MAXIMUM_CONTRIBUTORS;
    }

    function getMilestoneUpdateTimelock() public view returns (uint) {
        return _milestoneUpdateTimelock;
    }

    //--------------------------------------------------------------------------
    // Milestone API Functions

    /// @inheritdoc IMilestoneManager
    function addMilestone(
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external onlyAuthorizedOrOwner returns (uint) {
        _validateMilestoneDetails(duration, budget, contributors, details);

        Milestone memory _mlstn =
            _createMilestoneInstance(duration, budget, contributors, details);

        return _addMilestoneInstance(_mlstn);
    }

    /// @inheritdoc IMilestoneManager
    function stopMilestone(uint prevId, uint id)
        external
        onlyAuthorizedOrOwner
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

        // Update _milestones list
        _milestones[prevId] = _milestones[id];

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

        IMilestoneManager.Contributor[] memory contribCache = m.contributors;

        if (m.budget != 0) {
            //substract the fee from the budget and send it to treasury
            uint feePayout = ((m.budget / SALARY_PRECISION) * FEE_PCT);

            m.budget -= feePayout;

            _ensureTokenBalance(feePayout);
            proposal().token().safeTransfer(FEE_TREASURY, feePayout);

            // Create payment order for each contributor of the new  milestone.
            uint len = contribCache.length;
            for (uint i; i < len; ++i) {
                // Calculate the payout amount.
                uint contributorPayout =
                    ((m.budget / SALARY_PRECISION) * contribCache[i].salary);

                // Note that the payout SHOULD be fulfilled before the end of the milestone's duration.
                _addPaymentOrder(contribCache[i].addr, contributorPayout,
                    block.timestamp + m.duration);
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
    ) external onlyAuthorizedOrOwner validId(id) {
        _validateMilestoneDetails(duration, budget, contributors, details);

        Milestone storage m = _milestoneRegistry[id];

        // Not updateable if milestone started already.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotUpdateable();
        }

        // Not updateable if milestone is already completed.
        if (m.completed) {
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
        onlyAuthorizedOrOwner
        validId(id)
        validPosition(idToPositionAfter)
        validPosition(prevId)
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
        onlyAuthorizedOrOwner
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
        onlyAuthorizedOrOwner
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

    /// @notice Creates a memory instance of the milestone we want to add
    /// @dev sub-function created to circumvent stackTooDeep errors
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param contributors The contributor information for the milestone
    /// @param details The milestone's details.
    /// @return The newly created milestone.
    function _createMilestoneInstance(
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    ) internal view returns (Milestone memory) {
        Milestone memory _mlstn = Milestone({
            duration: duration,
            budget: budget,
            contributors: contributors,
            details: details,
            startTimestamp: 0,
            submissionData: "",
            completed: false,
            lastUpdatedTimestamp: block.timestamp
        });

        return _mlstn;
    }

    /// @notice Adds a milestone instance to the list of current milestones
    /// @dev sub-function created to circumvent stackTooDeep errors
    /// @param milestone The milestone we want to add.
    /// @return _id The newly added milestone's id.
    function _addMilestoneInstance(Milestone memory milestone)
        internal
        returns (uint _id)
    {
        // Increase counter and cache result.
        // Note that ids therefore start at 1.
        uint milestoneId = ++_milestoneCounter;

        // Add milestone's id to end of list.
        _milestones[_last] = milestoneId;
        _milestones[milestoneId] = _SENTINEL;
        _last = milestoneId;

        // Add milestone instance to registry.
        _milestoneRegistry[milestoneId].duration = milestone.duration;
        _milestoneRegistry[milestoneId].budget = milestone.budget;

        uint len = milestone.contributors.length;
        for (uint i; i < len; ++i) {
            _milestoneRegistry[milestoneId].contributors.push(
                milestone.contributors[i]
            );
        }

        _milestoneRegistry[milestoneId].details = milestone.details;
        _milestoneRegistry[milestoneId].startTimestamp = 0;
        _milestoneRegistry[milestoneId].submissionData = "";
        _milestoneRegistry[milestoneId].completed = false;
        _milestoneRegistry[milestoneId].lastUpdatedTimestamp = block.timestamp;

        emit MilestoneAdded(
            milestoneId,
            milestone.duration,
            milestone.budget,
            milestone.contributors,
            milestone.details
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
            // Trigger delegatecall-callback from proposal to transfer tokens
            // to address(this).
            bool ok;
            (ok, /*returnData*/ ) = _triggerProposalCallback(
                abi.encodeWithSignature(
                    "__Proposal_transferERC20(address,uint256)",
                    address(this),
                    amount - balance
                ),
                Types.Operation.DelegateCall
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

    //--------------------------------------------------------------------------
    // Proposal Callback Functions

    /// @dev WantProposalContext-callback function to transfer `amount` of
    ///      tokens from proposal to `receiver`.
    /// @dev For more info, see src/modules/base/Module.sol.
    function __Proposal_transferERC20(address receiver, uint amount)
        external
        wantProposalContext
    {
        __Proposal__token.safeTransfer(receiver, amount);
    }
}
