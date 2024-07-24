// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IAUT_EXT_VotingRoles_v1} from
    "src/modules/authorizer/role/interfaces/IAUT_EXT_VotingRoles_v1.sol";

// Internal Dependencies
import {ERC165, Module_v1} from "src/modules/base/Module_v1.sol";
/**
 * @title   Voting Role Manager
 *
 * @notice  Facilitates voting and motion management within the Inverter Network,
 *          allowing designated voters to participate in governance through proposals,
 *          voting, and execution of decisions.
 *
 * @dev     Supports setting thresholds for decision-making, managing voter lists,
 *          creating motions, casting votes, and executing actions based on collective
 *          decisions. This structure enhances governance transparency and efficacy.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */

contract AUT_EXT_VotingRoles_v1 is IAUT_EXT_VotingRoles_v1, Module_v1 {
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IAUT_EXT_VotingRoles_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev Reverts if caller is not the module itself.
    modifier onlySelf() {
        if (_msgSender() != address(this)) {
            revert Module__CallerNotAuthorized(
                bytes32("onlySelf"), _msgSender()
            );
        }
        _;
    }

    /// @dev Reverts if caller is not a voter.
    modifier onlyVoter() {
        if (!isVoter[_msgSender()]) {
            revert Module__VotingRoleManager__CallerNotVoter();
        }
        _;
    }

    /// @dev Reverts if voter address is invalid.
    /// @param voter The address to check.
    modifier isValidVoterAddress(address voter) {
        if (
            voter == address(0) || voter == address(this)
                || voter == address(orchestrator())
        ) {
            revert Module__VotingRoleManager__InvalidVoterAddress();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    uint public constant MAX_VOTING_DURATION = 2 weeks;

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    uint public constant MIN_VOTING_DURATION = 1 days;

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    mapping(address => bool) public isVoter;

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    mapping(bytes32 => Motion) public motions;

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    uint public motionCount;

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    uint public voterCount;

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    uint public threshold;

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    uint public voteDuration;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override initializer {
        __Module_init(orchestrator_, metadata);

        // Decode configData to list of voters, the required threshold, and the
        // voting duration.
        address[] memory voters;
        uint threshold_;
        uint voteDuration_;
        (voters, threshold_, voteDuration_) =
            abi.decode(configData, (address[], uint, uint));

        uint votersLen = voters.length;

        // Revert if list of voters is empty.
        if (votersLen == 0) {
            revert Module__VotingRoleManager__EmptyVoters();
        }

        // Revert if the threshold is set incorrectly
        validateThreshold(votersLen, threshold_);

        // Revert if votingDuration outside of bounds.
        if (
            voteDuration_ < MIN_VOTING_DURATION
                || voteDuration_ > MAX_VOTING_DURATION
        ) {
            revert Module__VotingRoleManager__InvalidVotingDuration();
        }

        // Write voters to storage.
        address voter;
        for (uint i; i < votersLen; ++i) {
            voter = voters[i];

            if (
                voter == address(0) || voter == address(this)
                    || voter == address(orchestrator())
            ) {
                revert Module__VotingRoleManager__InvalidVoterAddress();
            }

            if (isVoter[voter]) {
                revert Module__VotingRoleManager__IsAlreadyVoter();
            }

            isVoter[voter] = true;
            emit VoterAdded(voter);
        }

        // Write count of voters to storage.
        voterCount = votersLen;

        // Write threshold to storage.
        threshold = threshold_;
        emit ThresholdUpdated(0, threshold_);

        // Write voteDuration to storage.
        voteDuration = voteDuration_;
        emit VoteDurationUpdated(0, voteDuration_);
    }

    //--------------------------------------------------------------------------
    // Data Retrieval Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function getReceipt(bytes32 _ID, address voter)
        public
        view
        returns (Receipt memory)
    {
        Receipt memory _r = motions[_ID].receipts[voter];

        return (_r);
    }

    //--------------------------------------------------------------------------
    // Configuration Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function setThreshold(uint newThreshold) public onlySelf {
        // Revert if the threshold is set incorrectly
        validateThreshold(voterCount, newThreshold);

        emit ThresholdUpdated(threshold, newThreshold);
        threshold = newThreshold;
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function setVotingDuration(uint newVoteDuration) external onlySelf {
        // Revert if votingDuration outside of bounds.
        if (
            newVoteDuration < MIN_VOTING_DURATION
                || newVoteDuration > MAX_VOTING_DURATION
        ) {
            revert Module__VotingRoleManager__InvalidVotingDuration();
        }

        emit VoteDurationUpdated(voteDuration, newVoteDuration);
        voteDuration = newVoteDuration;
    }

    //--------------------------------------------------------------------------
    // Voter Management Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function addVoter(address who) public onlySelf isValidVoterAddress(who) {
        if (!isVoter[who]) {
            isVoter[who] = true;
            unchecked {
                ++voterCount;
            }
            emit VoterAdded(who);
        }
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function addVoterAndUpdateThreshold(address who, uint newThreshold)
        external
    {
        // Add the new voter
        addVoter(who);

        // Set the new threshold (also validates it)
        setThreshold(newThreshold);
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function removeVoter(address who) public onlySelf {
        _removeVoter(who);

        // Revert if the threshold would be invalid after this
        validateThreshold(voterCount, threshold);
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function removeVoterAndUpdateThreshold(address who, uint newThreshold)
        external
        onlySelf
    {
        _removeVoter(who);

        // Set the new threshold (also validates it)
        setThreshold(newThreshold);
    }

    /// @dev Removes a voter from the list of voters.
    /// @param who The address of the voter to remove.
    function _removeVoter(address who) internal {
        // Revert if trying to remove the last voter
        if (voterCount == 1) {
            revert Module__VotingRoleManager__EmptyVoters();
        }

        if (isVoter[who]) {
            delete isVoter[who];
            unchecked {
                --voterCount;
            }
            emit VoterRemoved(who);
        }
    }

    //--------------------------------------------------------------------------
    // Governance Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function createMotion(address target, bytes calldata action)
        external
        onlyVoter
        returns (bytes32)
    {
        // Cache motion's id.
        bytes32 motionId =
            keccak256(abi.encodePacked(target, action, motionCount));

        // Get pointer to motion.
        // Note that the motion instance is uninitialized.
        Motion storage motion_ = motions[motionId];

        // Initialize motion.
        motion_.target = target;
        motion_.action = action;

        motion_.startTimestamp = block.timestamp;
        motion_.endTimestamp = block.timestamp + voteDuration;
        motion_.requiredThreshold = threshold;

        emit MotionCreated(motionId);

        // Increase the motion count.
        unchecked {
            ++motionCount;
        }

        return motionId;
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function castVote(bytes32 motionId, uint8 support) external onlyVoter {
        // Revert if support invalid.
        // 0 = for
        // 1 = against
        // 2 = abstain
        if (support > 2) {
            revert Module__VotingRoleManager__InvalidSupport();
        }

        // Get pointer to the motion.
        Motion storage motion_ = motions[motionId];

        // Revert if motionID invalid
        if (motion_.startTimestamp == 0) {
            revert Module__VotingRoleManager__InvalidMotionId();
        }

        // Revert if voting duration exceeded
        if (block.timestamp > motion_.endTimestamp) {
            revert Module__VotingRoleManager__MotionVotingPhaseClosed();
        }

        // Revert if caller attempts to double vote.
        if (motion_.receipts[_msgSender()].hasVoted) {
            revert Module__VotingRoleManager__AttemptedDoubleVote();
        }

        if (support == 0) {
            unchecked {
                ++motion_.forVotes;
            }
        } else if (support == 1) {
            unchecked {
                ++motion_.againstVotes;
            }
        } else if (support == 2) {
            unchecked {
                ++motion_.abstainVotes;
            }
        }

        address voter = _msgSender();

        motion_.receipts[voter] = Receipt(true, support);

        emit VoteCast(motionId, voter, support);
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v1
    function executeMotion(bytes32 motionId) external {
        // Get pointer to the motion.
        Motion storage motion_ = motions[motionId];

        // Revert if motionId invalid.
        if (motion_.startTimestamp == 0) {
            revert Module__VotingRoleManager__InvalidMotionId();
        }

        // Revert if voting duration not exceeded.
        if (block.timestamp <= motion_.endTimestamp) {
            revert Module__VotingRoleManager__MotionInVotingPhase();
        }

        // Revert if necessary threshold was not reached
        if (motion_.forVotes < motion_.requiredThreshold) {
            revert Module__VotingRoleManager__ThresholdNotReached();
        }

        // Revert if motion already executed.
        if (motion_.executedAt != 0) {
            revert Module__VotingRoleManager__MotionAlreadyExecuted();
        }

        // Updating executedAt here to prevent reentrancy
        motion_.executedAt = block.timestamp;

        // Execute `action` on `target`.
        bool result;
        bytes memory returnData;
        (result, returnData) = motion_.target.call(motion_.action);

        // Save execution's result.
        motion_.executionResult = result;
        motion_.executionReturnData = returnData;

        emit MotionExecuted(motionId);
    }

    //--------------------------------------------------------------------------
    // Internal

    function validateThreshold(uint _voters, uint _threshold) internal pure {
        // Revert if one of these conditions is met
        // - Threshold is higher than the amount of voters
        // - There are less than 3 voters and the threshold is set to 0
        // - There are 3 or more voters and the threshold is less than 2
        if (
            _threshold > _voters || (_voters >= 3 && _threshold < 2)
                || (_voters < 3 && _threshold == 0)
        ) {
            revert Module__VotingRoleManager__InvalidThreshold();
        }
    }
}
