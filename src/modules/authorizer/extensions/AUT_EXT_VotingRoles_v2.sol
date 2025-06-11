// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v2} from "src/modules/base/IModule_v2.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IAUT_EXT_VotingRoles_v2} from
    "src/modules/authorizer/extensions/interfaces/IAUT_EXT_VotingRoles_v2.sol";

// Internal Dependencies
import {ERC165Upgradeable, Module_v2} from "src/modules/base/Module_v2.sol";
/**
 * @title   Inverter Voting Role Manager
 *
 * @notice  Facilitates voting and motion management within the Inverter
 *          Network, allowing designated voters to participate in governance
 *          through proposals, voting, and execution of decisions.
 *
 * @dev     Supports setting thresholds for decision-making, managing voter
 *          lists, creating _motions, casting votes, and executing actions
 *          based on collective decisions. This structure enhances governance
 *          transparency and efficacy.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */

contract AUT_EXT_VotingRoles_v2 is IAUT_EXT_VotingRoles_v2, Module_v2 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v2)
        returns (bool isInterfaceId_)
    {
        return interfaceId_ == type(IAUT_EXT_VotingRoles_v2).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //==========================================================================
    // Modifiers

    /// @notice	Reverts if caller is not the module itself.
    modifier onlySelf() {
        if (_msgSender() != address(this)) {
            revert Module__VotingRoleManager__OnlySelfCallAllowed();
        }
        _;
    }

    /// @notice	Reverts if caller is not a voter.
    modifier onlyVoter() {
        if (!_isVoter[_msgSender()]) {
            revert Module__VotingRoleManager__CallerNotVoter();
        }
        _;
    }

    /// @notice	Reverts if voter address is invalid.
    /// @param  voter_ The address to check.
    modifier isValidVoterAddress(address voter_) {
        if (
            voter_ == address(0) || voter_ == address(this)
                || voter_ == address(orchestrator())
        ) {
            revert Module__VotingRoleManager__InvalidVoterAddress();
        }
        _;
    }

    //==========================================================================
    // Constants

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    uint public constant MAX_VOTING_DURATION = 2 weeks;

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    uint public constant MIN_VOTING_DURATION = 1 days;

    //==========================================================================
    // Storage

    /// @notice Mapping that stores if an address is a voter.
    mapping(address voter => bool isVoter) internal _isVoter;

    /// @notice Mapping that stores the motions.
    mapping(bytes32 motionId => Motion motion) internal _motions;

    /// @notice The counter for motions.
    uint internal _motionCount;

    /// @notice The counter for voters.
    uint internal _voterCount;

    /// @notice The threshold for motions.
    uint internal _threshold;

    /// @notice The duration for voting.
    uint internal _voteDuration;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    //==========================================================================
    // Initialization

    /// @inheritdoc Module_v2
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override initializer {
        __Module_init(orchestrator_, metadata_);

        // Decode configData to list of voters, the required threshold, and the
        // voting duration.
        address[] memory voters;
        uint threshold;
        uint voteDuration;
        (voters, threshold, voteDuration) =
            abi.decode(configData_, (address[], uint, uint));

        uint votersLen = voters.length;

        // Revert if list of voters is empty.
        if (votersLen == 0) {
            revert Module__VotingRoleManager__EmptyVoters();
        }

        // Revert if the threshold is set incorrectly.
        _validateThreshold(votersLen, threshold);

        // Revert if votingDuration outside of bounds.
        if (
            voteDuration < MIN_VOTING_DURATION
                || voteDuration > MAX_VOTING_DURATION
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

            if (_isVoter[voter]) {
                revert Module__VotingRoleManager__IsAlreadyVoter();
            }

            _isVoter[voter] = true;
            emit VoterAdded(voter);
        }

        // Write count of voters to storage.
        _voterCount = votersLen;

        // Write threshold to storage.
        _threshold = threshold;
        emit ThresholdUpdated(0, threshold);

        // Write _voteDuration to storage.
        _voteDuration = voteDuration;
        emit VoteDurationUpdated(0, voteDuration);
    }

    //==========================================================================
    // Getter Functions

    //--------------------------------------------------------------------------
    // Getter - State Access Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function isVoter(address who_) external view returns (bool isVoter_) {
        return _isVoter[who_];
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function getMotion(bytes32 id_)
        external
        view
        returns (
            address target_,
            bytes memory action_,
            uint startTimestamp_,
            uint endTimestamp_,
            uint requiredThreshold_,
            uint forVotes_,
            uint againstVotes_,
            uint abstainVotes_,
            uint executedAt_,
            bool executionResult_,
            bytes memory executionReturnData_
        )
    {
        Motion storage motion_ = _motions[id_];

        return (
            motion_.target,
            motion_.action,
            motion_.startTimestamp,
            motion_.endTimestamp,
            motion_.requiredThreshold,
            motion_.forVotes,
            motion_.againstVotes,
            motion_.abstainVotes,
            motion_.executedAt,
            motion_.executionResult,
            motion_.executionReturnData
        );
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function getMotionCount() external view returns (uint motionCount_) {
        return _motionCount;
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function getVoterCount() external view returns (uint voterCount_) {
        return _voterCount;
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function getThreshold() external view returns (uint threshold_) {
        return _threshold;
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function getVoteDuration() external view returns (uint voteDuration_) {
        return _voteDuration;
    }

    //--------------------------------------------------------------------------
    // Data Retrieval Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function getReceipt(bytes32 id_, address voter_)
        public
        view
        returns (Receipt memory receipt_)
    {
        Receipt memory r = _motions[id_].receipts[voter_];

        return (r);
    }

    //==========================================================================
    // Mutating Functions

    //--------------------------------------------------------------------------
    // Mutating - Configuration Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function setThreshold(uint newThreshold_) public onlySelf {
        // Revert if the threshold is set incorrectly.
        _validateThreshold(_voterCount, newThreshold_);

        emit ThresholdUpdated(_threshold, newThreshold_);
        _threshold = newThreshold_;
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function setVotingDuration(uint newVoteDuration_) external onlySelf {
        // Revert if votingDuration outside of bounds.
        if (
            newVoteDuration_ < MIN_VOTING_DURATION
                || newVoteDuration_ > MAX_VOTING_DURATION
        ) {
            revert Module__VotingRoleManager__InvalidVotingDuration();
        }

        emit VoteDurationUpdated(_voteDuration, newVoteDuration_);
        _voteDuration = newVoteDuration_;
    }

    //--------------------------------------------------------------------------
    // Mutating - Voter Management Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function addVoter(address who_) public onlySelf isValidVoterAddress(who_) {
        if (!_isVoter[who_]) {
            _addVoter(who_);
            // Validate threshold after adding voter.
            _validateThreshold(_voterCount, _threshold);
        }
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function addVoterAndUpdateThreshold(address who_, uint newThreshold_)
        external
    {
        if (!_isVoter[who_]) {
            // Add the new voter.
            _addVoter(who_);
        }
        // Set the new threshold (also validates it).
        setThreshold(newThreshold_);
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function removeVoter(address who_) public onlySelf {
        _removeVoter(who_);

        // Revert if the threshold would be invalid after this.
        _validateThreshold(_voterCount, _threshold);
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function removeVoterAndUpdateThreshold(address who_, uint newThreshold_)
        external
        onlySelf
    {
        _removeVoter(who_);

        // Set the new threshold (also validates it).
        setThreshold(newThreshold_);
    }

    //--------------------------------------------------------------------------
    // Mutating - Governance Functions

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function createMotion(address target_, bytes calldata action_)
        external
        onlyVoter
        returns (bytes32 motionId_)
    {
        // Cache motion's id.
        bytes32 motionId =
            keccak256(abi.encodePacked(target_, action_, _motionCount));

        // Get pointer to motion.
        // Note that the motion instance is uninitialized.
        Motion storage motion_ = _motions[motionId];

        // Initialize motion.
        motion_.target = target_;
        motion_.action = action_;

        motion_.startTimestamp = block.timestamp;
        motion_.endTimestamp = block.timestamp + _voteDuration;
        motion_.requiredThreshold = _threshold;

        emit MotionCreated(motionId);

        // Increase the motion count.
        unchecked {
            ++_motionCount;
        }

        return motionId;
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function castVote(bytes32 motionId_, uint8 support_) external onlyVoter {
        // Revert if support invalid.
        // - 0 = for
        // - 1 = against
        // - 2 = abstain
        if (support_ > 2) {
            revert Module__VotingRoleManager__InvalidSupport();
        }

        // Get pointer to the motion.
        Motion storage motion_ = _motions[motionId_];

        // Revert if motionID invalid.
        if (motion_.startTimestamp == 0) {
            revert Module__VotingRoleManager__InvalidMotionId();
        }

        // Revert if voting duration exceeded.
        if (block.timestamp > motion_.endTimestamp) {
            revert Module__VotingRoleManager__MotionVotingPhaseClosed();
        }

        // Revert if caller attempts to double vote.
        if (motion_.receipts[_msgSender()].hasVoted) {
            revert Module__VotingRoleManager__AttemptedDoubleVote();
        }

        if (support_ == 0) {
            unchecked {
                ++motion_.forVotes;
            }
        } else if (support_ == 1) {
            unchecked {
                ++motion_.againstVotes;
            }
        } else if (support_ == 2) {
            unchecked {
                ++motion_.abstainVotes;
            }
        }

        address voter = _msgSender();

        motion_.receipts[voter] = Receipt(true, support_);

        emit VoteCast(motionId_, voter, support_);
    }

    /// @inheritdoc IAUT_EXT_VotingRoles_v2
    function executeMotion(bytes32 motionId_) external {
        // Get pointer to the motion.
        Motion storage motion_ = _motions[motionId_];

        // Revert if motionId invalid.
        if (motion_.startTimestamp == 0) {
            revert Module__VotingRoleManager__InvalidMotionId();
        }

        // Revert if voting duration not exceeded.
        if (block.timestamp <= motion_.endTimestamp) {
            revert Module__VotingRoleManager__MotionInVotingPhase();
        }

        // Revert if necessary threshold was not reached.
        if (motion_.forVotes < motion_.requiredThreshold) {
            revert Module__VotingRoleManager__ThresholdNotReached();
        }

        // Revert if motion already executed.
        if (motion_.executedAt != 0) {
            revert Module__VotingRoleManager__MotionAlreadyExecuted();
        }

        // Updating executedAt here to prevent reentrancy.
        motion_.executedAt = block.timestamp;

        // Execute `action` on `target`.
        bool result;
        bytes memory returnData;
        (result, returnData) = motion_.target.call(motion_.action);

        // Save execution's result.
        motion_.executionResult = result;
        motion_.executionReturnData = returnData;

        emit MotionExecuted(motionId_);
    }

    //==========================================================================
    // Internal Functions

    /// @notice	Removes a voter from the list of voters.
    /// @param  who_ The address of the voter to remove.
    function _removeVoter(address who_) internal {
        // Revert if trying to remove the last voter.
        if (_voterCount == 1) {
            revert Module__VotingRoleManager__EmptyVoters();
        }

        if (_isVoter[who_]) {
            delete _isVoter[who_];
            unchecked {
                --_voterCount;
            }
            emit VoterRemoved(who_);
        }
    }

    /// @notice	Internal function to validate the threshold.
    /// @param  voters_ The number of voters.
    /// @param  threshold_ The threshold.
    function _validateThreshold(uint voters_, uint threshold_) internal pure {
        // Revert if one of these conditions is met:
        // - Threshold is higher than the amount of voters
        // - There are less than 3 voters and the threshold is set to 0
        // - There are 3 or more voters and the threshold is less than 2
        if (
            threshold_ > voters_ || (voters_ >= 3 && threshold_ < 2)
                || (voters_ < 3 && threshold_ == 0)
        ) {
            revert Module__VotingRoleManager__InvalidThreshold();
        }
    }

    /// @notice	Internal function to add a voter to the list of voters.
    /// @dev    This function does not validate the threshold.
    /// @param  voter_ The address of the voter to add.
    function _addVoter(address voter_) internal {
        _isVoter[voter_] = true;
        unchecked {
            ++_voterCount;
        }

        emit VoterAdded(voter_);
    }
}
