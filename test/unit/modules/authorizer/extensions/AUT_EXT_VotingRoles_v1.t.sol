// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

// SuT
import {
    AUT_EXT_VotingRoles_v1,
    IAUT_EXT_VotingRoles_v1
} from "src/modules/authorizer/extensions/AUT_EXT_VotingRoles_v1.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// Internal Dependencies
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

// Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Mocks
import {ModuleV1Mock} from "test/utils/mocks/modules/base/ModuleV1Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {FundingManagerV1Mock} from
    "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "test/utils/mocks/modules/PaymentProcessorV1Mock.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract AUT_EXT_VotingRoles_v1Test is ModuleTest {
    // SuT
    AUT_EXT_VotingRoles_v1 _votingRoles;

    // Orchestrator_v1 _orchestrator;
    address[] initialVoters;
    address[] currentVoters;

    // Constants and other data structures
    uint internal constant DEFAULT_QUORUM = 2;
    uint internal constant DEFAULT_DURATION = 4 days;

    // intial authorizd users
    address internal constant ALBA = address(0xa1ba);
    address internal constant BOB = address(0xb0b);
    address internal constant COBIE = address(0xc0b1e);
    IAUT_EXT_VotingRoles_v1.Motion _bufMotion;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new voter address gets added.
    /// @param  who The added address.
    event VoterAdded(address indexed who);

    /// @notice Event emitted when a voter address gets removed.
    /// @param  who The removed address.
    event VoterRemoved(address indexed who);

    /// @notice Event emitted when the required threshold changes.
    /// @param  oldThreshold The old threshold.
    /// @param  newThreshold The new threshold.
    event ThresholdUpdated(uint oldThreshold, uint newThreshold);

    /// @notice Event emitted when the voting duration changes.
    /// @param  oldVotingDuration The old voting duration.
    /// @param  newVotingDuration The new voting duration.
    event VoteDurationUpdated(uint oldVotingDuration, uint newVotingDuration);

    /// @notice Event emitted when a motion is created
    /// @param  motionId The motion ID.
    event MotionCreated(bytes32 indexed motionId);

    event VoteCast(
        bytes32 indexed motionId, address indexed voter, uint8 indexed support
    );

    /// @notice Event emitted when a motion is executed.
    /// @param  motionId The motion ID.
    event MotionExecuted(bytes32 indexed motionId);

    function setUp() public {
        // Set up a orchestrator
        address authImpl = address(new AUT_EXT_VotingRoles_v1());
        _votingRoles = AUT_EXT_VotingRoles_v1(Clones.clone(authImpl));

        _setUpOrchestrator(_votingRoles);

        // we give the votingRoles the ownwer role
        bytes32 adminRole = _authorizer.getAdminRole();
        _authorizer.grantRole(adminRole, address(_votingRoles));
        // _authorizer.setIsAuthorized(address(_votingRoles), true);

        // Initialize the votingRoles with 3 users

        initialVoters = new address[](3);
        initialVoters[0] = ALBA;
        initialVoters[1] = BOB;
        initialVoters[2] = COBIE;

        uint _startingThreshold = DEFAULT_QUORUM;
        uint _startingDuration = DEFAULT_DURATION;

        _votingRoles.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(initialVoters, _startingThreshold, _startingDuration)
        );

        currentVoters.push(ALBA);
        currentVoters.push(BOB);
        currentVoters.push(COBIE);

        // validation of the initial state happens in testInit()
    }

    function testSupportsInterface() public {
        assertTrue(
            _votingRoles.supportsInterface(
                type(IAUT_EXT_VotingRoles_v1).interfaceId
            )
        );
    }

    //--------------------------------------------------------------------------
    // Helper functions for common functionalities
    function createVote(address callingUser, address _addr, bytes memory _msg)
        public
        returns (bytes32)
    {
        bytes32 countID =
            keccak256(abi.encodePacked(_addr, _msg, _votingRoles.motionCount()));
        vm.prank(callingUser);

        vm.expectEmit(true, true, true, true);
        emit MotionCreated(countID);

        bytes32 _id = _votingRoles.createMotion(_addr, _msg);
        return _id;
    }

    function batchAddAuthorized(address[] memory users) public {
        for (uint i; i < users.length; ++i) {
            // We add a new address through governance.
            bytes memory _encodedAction =
                abi.encodeWithSignature("addVoter(address)", users[i]);
            // for ease, we are assuming this is happening before any threshold changes
            bytes32 _voteID = speedrunSuccessfulVote(
                address(_votingRoles), _encodedAction, initialVoters
            );
            _votingRoles.executeMotion(_voteID);

            currentVoters.push(users[i]);
            assertEq(_votingRoles.isVoter(users[i]), true);
        }
    }

    function voteInFavor(address callingUser, bytes32 voteID) public {
        uint8 vote = 0;

        vm.prank(callingUser);
        _votingRoles.castVote(voteID, vote);
    }

    function voteAgainst(address callingUser, bytes32 voteID) public {
        uint8 vote = 1;

        vm.prank(callingUser);
        _votingRoles.castVote(voteID, vote);
    }

    function voteAbstain(address callingUser, bytes32 voteID) public {
        uint8 vote = 2;

        vm.prank(callingUser);
        _votingRoles.castVote(voteID, vote);
    }

    function speedrunSuccessfulVote(
        address _target,
        bytes memory _action,
        address[] memory _voters
    ) public returns (bytes32) {
        if (_voters.length == 0) {
            revert("Voterlist empty");
        }
        bytes32 _voteID = createVote(_voters[0], _target, _action);

        for (uint i; i < _voters.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit VoteCast(_voteID, _voters[i], 0);
            voteInFavor(_voters[i], _voteID);
        }

        // the voting time passes
        vm.warp(block.timestamp + _votingRoles.voteDuration() + 1);

        return _voteID;
    }

    function speedrunRejectedVote(
        address _target,
        bytes memory _action,
        address[] memory _voters
    ) public returns (bytes32) {
        if (_voters.length == 0) {
            revert("Voterlist empty");
        }
        bytes32 _voteID = createVote(_voters[0], _target, _action);

        for (uint i = 1; i < _votingRoles.threshold(); ++i) {
            if (i < _voters.length) {
                vm.expectEmit(true, true, true, true);
                emit VoteCast(_voteID, _voters[(i - 1)], 0);
                voteInFavor(_voters[(i - 1)], _voteID);
            }
        }

        // the voting time passes
        vm.warp(block.timestamp + _votingRoles.voteDuration() + 1);

        return _voteID;
    }

    function getMockValidVote() public view returns (address, bytes memory) {
        address _moduleAddress = address(_votingRoles);
        bytes memory _msg = abi.encodeWithSignature("setThreshold(uint)", 1);

        return (_moduleAddress, _msg);
    }

    function getFullMotionData(bytes32 voteId)
        internal
        returns (IAUT_EXT_VotingRoles_v1.Motion storage)
    {
        (
            address _addr,
            bytes memory _act,
            uint _start,
            uint _end,
            uint _threshold,
            uint _for,
            uint _against,
            uint _abstain,
            uint _excAt,
            bool _excRes,
            bytes memory _excData
        ) = _votingRoles.motions(voteId);

        _bufMotion.target = _addr;
        _bufMotion.action = _act;
        _bufMotion.startTimestamp = _start;
        _bufMotion.endTimestamp = _end;
        _bufMotion.requiredThreshold = _threshold;
        _bufMotion.forVotes = _for;
        _bufMotion.againstVotes = _against;
        _bufMotion.abstainVotes = _abstain;
        _bufMotion.executedAt = _excAt;
        _bufMotion.executionResult = _excRes;
        _bufMotion.executionReturnData = _excData;

        for (uint i; i < currentVoters.length; ++i) {
            _bufMotion.receipts[currentVoters[i]] =
                _votingRoles.getReceipt(voteId, currentVoters[i]);
        }

        return _bufMotion;
    }

    //--------------------------------------------------------------------------
    // TESTS: INITIALIZATION

    function testInit() public override(ModuleTest) {
        assertEq(_orchestrator.isModule(address(_votingRoles)), true);

        bytes32 admin = _authorizer.getAdminRole();

        assertEq(_authorizer.hasRole(admin, address(_votingRoles)), true); // Admin role
        assertEq(_votingRoles.isVoter(ALBA), true);
        assertEq(_votingRoles.isVoter(BOB), true);
        assertEq(_votingRoles.isVoter(COBIE), true);
        assertEq(_authorizer.hasRole(admin, address(this)), true);
        assertEq(_authorizer.hasRole(admin, address(_orchestrator)), false);
        assertEq(_votingRoles.isVoter(address(this)), false);
        assertEq(_votingRoles.isVoter(address(_orchestrator)), false);

        assertEq(_votingRoles.voterCount(), 3);
    }

    function testInitWithInitialVoters(address[] memory testVoters) public {
        // Checks that address list gets correctly stored on initialization
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        vm.assume(testVoters.length >= 2);
        _validateUserList(testVoters);

        address authImpl = address(new AUT_EXT_VotingRoles_v1());
        AUT_EXT_VotingRoles_v1 testAuthorizer =
            AUT_EXT_VotingRoles_v1(Clones.clone(authImpl));

        // Since the authorizer we are working with is not the default one,
        // we must manually control that the fuzzer doesn't feed us its address
        for (uint i; i < testVoters.length; ++i) {
            vm.assume(testVoters[i] != address(testAuthorizer));
        }

        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        assertEq(address(testAuthorizer.orchestrator()), address(_orchestrator));

        for (uint i; i < testVoters.length; ++i) {
            assertEq(testAuthorizer.isVoter(testVoters[i]), true);
        }
        assertEq(testAuthorizer.isVoter(address(this)), false);
        assertEq(testAuthorizer.voterCount(), testVoters.length);
    }

    function testInitWithDuplicateInitialVotersFails(
        address[] memory testVoters,
        uint8 position
    ) public {
        // Checks that address list gets correctly stored on initialization
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        vm.assume(testVoters.length >= 2);
        position = uint8(bound(position, 1, testVoters.length - 1));

        address authImpl = address(new AUT_EXT_VotingRoles_v1());
        AUT_EXT_VotingRoles_v1 testAuthorizer =
            AUT_EXT_VotingRoles_v1(Clones.clone(authImpl));

        _validateUserList(testVoters);

        // Since the authorizer we are working with is not the default one,
        // we must manually control that the fuzzer doesn't feed us its address
        for (uint i; i < testVoters.length; ++i) {
            vm.assume(testVoters[i] != address(testAuthorizer));
        }

        testVoters[position] = testVoters[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__IsAlreadyVoter
                    .selector
            )
        );
        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        _votingRoles.init(_orchestrator, _METADATA, bytes(""));
    }

    function testInitWithInvalidInitialVotersFails() public {
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        address authImpl = address(new AUT_EXT_VotingRoles_v1());
        AUT_EXT_VotingRoles_v1 testAuthorizer =
            AUT_EXT_VotingRoles_v1(Clones.clone(authImpl));

        address[] memory testVoters;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__EmptyVoters
                    .selector
            )
        );
        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        // test faulty list (zero addresses)
        testVoters = new address[](2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidVoterAddress
                    .selector
            )
        );
        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        testVoters[0] = address(testAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidVoterAddress
                    .selector
            )
        );
        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        testVoters[0] = address(_orchestrator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidVoterAddress
                    .selector
            )
        );
        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        assertEq(address(testAuthorizer.orchestrator()), address(0));
        assertEq(testAuthorizer.voterCount(), 0);
    }

    //--------------------------------------------------------------------------
    // TESTS: VOTE CREATION

    // Create vote correctly
    function testCreateVote() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        for (uint i; i < initialVoters.length; ++i) {
            bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

            IAUT_EXT_VotingRoles_v1.Motion storage _motion =
                getFullMotionData(_voteID);

            // assertEq(_votingRoles.motionCount(), (_voteID + 1));
            assertEq(_motion.target, _moduleAddress);
            assertEq(_motion.action, _msg);
            assertEq(_motion.startTimestamp, block.timestamp);
            assertEq(_motion.endTimestamp, (block.timestamp + DEFAULT_DURATION));
            assertEq(_motion.requiredThreshold, DEFAULT_QUORUM);
            assertEq(_motion.forVotes, 0);
            assertEq(_motion.againstVotes, 0);
            assertEq(_motion.abstainVotes, 0);
            assertEq(_motion.executedAt, 0);
            assertEq(_motion.executionResult, false);
            assertEq(_motion.executionReturnData, "");
        }
    }

    // Fail to create a vote as non-voting address
    function testUnauthorizedVoteCreation(address[] memory users) public {
        _validateUserList(users);

        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        for (uint i; i < users.length; ++i) {
            assertEq(_votingRoles.isVoter(users[i]), false);
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__CallerNotVoter
                    .selector
            );
            vm.prank(users[i]);
            _votingRoles.createMotion(_moduleAddress, _msg);
        }
    }

    function testUnauthorizedVoterAddition(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        for (uint i; i < users.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    bytes32("onlySelf"),
                    users[i]
                )
            );
            vm.prank(users[i]); // authorized, but not Module
            if (i % 3 == 0) {
                _votingRoles.addVoterAndUpdateThreshold(users[i], 3);
            } else {
                _votingRoles.addVoter(users[i]);
            }
        }
    }

    function testUnauthorizedVoterRemoval(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        for (uint i; i < users.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    bytes32("onlySelf"),
                    users[i]
                )
            );
            vm.prank(users[i]); // authorized, but not Module
            if (i % 3 == 0) {
                _votingRoles.removeVoterAndUpdateThreshold(users[i], 1);
            } else {
                _votingRoles.removeVoter(users[i]);
            }
        }
    }

    // Add authorized address and have it create a vote
    function testCreateVoteWithRecentlyAuthorizedAddress(address[] memory users)
        public
    {
        _validateUserList(users);

        batchAddAuthorized(users);

        for (uint i; i < users.length; ++i) {
            assertEq(_votingRoles.isVoter(users[i]), true);

            // prank as that address, create a vote and vote on it
            (address _moduleAddress, bytes memory _msg) = getMockValidVote();
            bytes32 _newVote = createVote(users[i], _moduleAddress, _msg);
            vm.expectEmit(true, true, true, true);
            emit VoteCast(_newVote, users[i], 0);
            voteInFavor(users[i], _newVote);

            // assert that voting worked (also confirms that vote exists)
            assertEq(_votingRoles.getReceipt(_newVote, users[i]).hasVoted, true);
        }
    }

    //--------------------------------------------------------------------------
    // TESTS: VOTING

    // Vote in favor at the beginning and at the end of the period
    function testVoteInFavor(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        // create a vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        IAUT_EXT_VotingRoles_v1.Motion storage _motion =
            getFullMotionData(_voteID);
        uint _votesBefore = _motion.forVotes;

        voteInFavor(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; ++i) {
            vm.warp(startTime + i);
            voteInFavor(users[i], _voteID);
        }

        // vote in the last possible moment
        vm.warp(startTime + DEFAULT_DURATION);
        voteInFavor(BOB, _voteID);

        _motion = getFullMotionData(_voteID);

        assertEq(_motion.receipts[ALBA].hasVoted, true);
        assertEq(_motion.receipts[ALBA].support, 0);

        assertEq(_motion.receipts[BOB].hasVoted, true);
        assertEq(_motion.receipts[BOB].support, 0);

        for (uint i; i < users.length; ++i) {
            assertEq(_motion.receipts[users[i]].hasVoted, true);
            assertEq(_motion.receipts[users[i]].support, 0);
        }

        assertEq(_motion.forVotes, (_votesBefore + 2 + users.length));
    }

    // Fail to vote in favor as unauthorized address
    function testVoteInFavorUnauthorized(address[] memory users) public {
        _validateUserList(users);

        // create vote as authorized user
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            // fail to vote as unauthorized address
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__CallerNotVoter
                    .selector
            );
            voteInFavor(users[i], _voteID);
        }
    }

    // Vote against at the beginning and at the end of the period
    function testVoteAgainst(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        // create a vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        IAUT_EXT_VotingRoles_v1.Motion storage _motion =
            getFullMotionData(_voteID);
        uint _votesBefore = _motion.againstVotes;

        vm.expectEmit(true, true, true, true);
        emit VoteCast(_voteID, ALBA, 1);
        voteAgainst(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; ++i) {
            vm.warp(startTime + i);
            vm.expectEmit(true, true, true, true);
            emit VoteCast(_voteID, users[i], 1);
            voteAgainst(users[i], _voteID);
        }

        // vote in the last possible moment
        vm.warp(startTime + DEFAULT_DURATION);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(_voteID, BOB, 1);
        voteAgainst(BOB, _voteID);

        _motion = getFullMotionData(_voteID);

        assertEq(_motion.receipts[ALBA].hasVoted, true);
        assertEq(_motion.receipts[ALBA].support, 1);

        assertEq(_motion.receipts[BOB].hasVoted, true);
        assertEq(_motion.receipts[BOB].support, 1);

        for (uint i; i < users.length; ++i) {
            assertEq(_motion.receipts[users[i]].hasVoted, true);
            assertEq(_motion.receipts[users[i]].support, 1);
        }

        assertEq(_motion.againstVotes, (_votesBefore + 2 + users.length));
    }

    // Fail to vote against as unauthorized address
    function testVoteAgainstUnauthorized(address[] memory users) public {
        _validateUserList(users);
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            // fail to vote as unauthorized address
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__CallerNotVoter
                    .selector
            );
            voteAgainst(users[i], _voteID);
        }
    }

    // Vote abstain at the beginning and at the end of the period
    function testAbstain(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        IAUT_EXT_VotingRoles_v1.Motion storage _motion =
            getFullMotionData(_voteID);
        uint _votesBefore = _motion.abstainVotes;

        vm.expectEmit(true, true, true, true);
        emit VoteCast(_voteID, ALBA, 2);
        voteAbstain(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; ++i) {
            vm.warp(startTime + i);
            vm.expectEmit(true, true, true, true);
            emit VoteCast(_voteID, users[i], 2);
            voteAbstain(users[i], _voteID);
        }

        // vote in the last possible moment
        vm.warp(startTime + DEFAULT_DURATION);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(_voteID, BOB, 2);
        voteAbstain(BOB, _voteID);

        IAUT_EXT_VotingRoles_v1.Receipt memory _r =
            _votingRoles.getReceipt(_voteID, ALBA);
        assertEq(_r.hasVoted, true);
        assertEq(_r.support, 2);

        _r = _votingRoles.getReceipt(_voteID, BOB);
        assertEq(_r.hasVoted, true);
        assertEq(_r.support, 2);

        for (uint i; i < users.length; ++i) {
            _r = _votingRoles.getReceipt(_voteID, users[i]);
            assertEq(_r.hasVoted, true);
            assertEq(_r.support, 2);
        }

        _motion = getFullMotionData(_voteID);

        assertEq(_motion.receipts[ALBA].hasVoted, true);
        assertEq(_motion.receipts[ALBA].support, 2);

        assertEq(_motion.receipts[BOB].hasVoted, true);
        assertEq(_motion.receipts[BOB].support, 2);

        for (uint i; i < users.length; ++i) {
            assertEq(_motion.receipts[users[i]].hasVoted, true);
            assertEq(_motion.receipts[users[i]].support, 2);
        }

        assertEq(_motion.abstainVotes, (_votesBefore + 2 + users.length));
    }

    // Fail to vote abstain as unauthorized address
    function testAbstainUnauthorized(address[] memory users) public {
        _validateUserList(users);
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            // fail to vote as unauthorized address
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__CallerNotVoter
                    .selector
            );
            voteAbstain(users[i], _voteID);
        }
    }

    // Fail to vote after vote is closed (testing the three vote variants)
    function testVoteOnExpired(uint[] memory nums) public {
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < nums.length; ++i) {
            nums[i] = bound(nums[i], 0, 100_000_000_000);
            vm.warp(block.timestamp + DEFAULT_DURATION + 1 + nums[i]);

            // For
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__MotionVotingPhaseClosed
                    .selector
            );

            voteInFavor(ALBA, _voteID);

            // Against
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__MotionVotingPhaseClosed
                    .selector
            );
            voteAgainst(ALBA, _voteID);

            // Abstain
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__MotionVotingPhaseClosed
                    .selector
            );
            voteAbstain(ALBA, _voteID);
        }
    }

    // Fail to vote on an unexisting voteID (testing the three vote variants)
    function testVoteOnUnexistingID(bytes32[] memory wrongIDs) public {
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < wrongIDs.length; ++i) {
            vm.assume(wrongIDs[i] != _voteID);
            bytes32 wrongID = wrongIDs[i];

            // For
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidMotionId
                    .selector
            );

            voteInFavor(ALBA, wrongID);

            // Against
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidMotionId
                    .selector
            );

            voteAgainst(ALBA, wrongID);

            // Abstain
            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidMotionId
                    .selector
            );
            voteAbstain(ALBA, wrongID);
        }
    }

    // Fail to vote with a different value than the allowed three
    function testCastInvalidVote(uint8 wrongVote) public {
        vm.assume(wrongVote > 2);
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__InvalidSupport
                .selector
        );
        vm.prank(ALBA);
        _votingRoles.castVote(_voteID, wrongVote);
    }

    // Fail vote for after already voting (testing the three vote variants)
    function testDoubleVoting(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            // vote once
            voteAgainst(users[i], _voteID);

            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__AttemptedDoubleVote
                    .selector
            );
            voteInFavor(users[i], _voteID);

            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__AttemptedDoubleVote
                    .selector
            );
            voteAgainst(users[i], _voteID);

            vm.expectRevert(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__AttemptedDoubleVote
                    .selector
            );
            voteAbstain(users[i], _voteID);
        }
    }

    //--------------------------------------------------------------------------
    // TEST: VOTE EXECUTION

    // Executing a vote that passed
    function testVoteExecution() public {
        // Here we will test a "standard" execution process to change the vote Duration. The process will be:

        // 1) Somebody creates a vote
        uint _newDuration = 2 days;
        bytes memory _encodedAction =
            abi.encodeWithSignature("setVotingDuration(uint256)", _newDuration);

        // 2) The vote passes
        bytes32 _voteID = speedrunSuccessfulVote(
            address(_votingRoles), _encodedAction, initialVoters
        );

        // 3) The vote gets executed (by anybody)

        vm.expectEmit(true, true, true, true);
        uint _oldDuration = _votingRoles.voteDuration();
        emit VoteDurationUpdated(_oldDuration, _newDuration);
        emit MotionExecuted(_voteID);
        _votingRoles.executeMotion(_voteID);

        // 4) The module state has changed
        assertEq(_votingRoles.voteDuration(), _newDuration);
    }
    // Fail to execute vote that didn't pass

    function testExecuteInexistentVote(bytes32 wrongId) public {
        // No votes exist yet, everyting should fail
        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__InvalidMotionId
                .selector
        );
        _votingRoles.executeMotion(wrongId);
    }

    // Fail to execute vote that didn't pass
    function testExecuteFailedVote() public {
        (address _moduleAddress, bytes memory _encodedAction) =
            getMockValidVote();

        bytes32 _voteID = speedrunRejectedVote(
            address(_moduleAddress), _encodedAction, initialVoters
        );

        // No prank address needed
        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__ThresholdNotReached
                .selector
        );
        _votingRoles.executeMotion(_voteID);
    }

    // Fail to execute vote while voting is open
    function testExecuteWhileVotingOpen() public {
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        bytes32 _voteID = createVote(ALBA, _moduleAddress, _msg);

        // First, we reach the threshold
        voteInFavor(ALBA, _voteID);
        voteInFavor(BOB, _voteID);

        vm.expectRevert(
            abi.encodePacked(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__MotionInVotingPhase
                    .selector
            )
        );
        _votingRoles.executeMotion(_voteID);

        // we wait and try again in the last block of voting time
        vm.warp(block.timestamp + _votingRoles.voteDuration());

        vm.expectRevert(
            abi.encodePacked(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__MotionInVotingPhase
                    .selector
            )
        );
        _votingRoles.executeMotion(_voteID);
    }

    // Fail to execute an already executed vote
    function testDoubleExecution() public {
        // 1) First we do a normal vote + execution
        uint _newDuration = 3 days;
        bytes memory _encodedAction =
            abi.encodeWithSignature("setVotingDuration(uint256)", _newDuration);
        bytes32 _voteID = speedrunSuccessfulVote(
            address(_votingRoles), _encodedAction, initialVoters
        );

        // 2) Then the vote gets executed by anybody
        _votingRoles.executeMotion(_voteID);

        // 3) the module state has changed
        assertEq(_votingRoles.voteDuration(), _newDuration);

        // 4) Now we test that we can't execute again:
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__MotionAlreadyExecuted
                    .selector
            )
        );
        _votingRoles.executeMotion(_voteID);
    }

    //--------------------------------------------------------------------------
    // TEST: VOTER MANAGEMENT
    function testAddVoters(address[] memory users) public {
        _validateUserList(users);

        vm.startPrank(address(_votingRoles));
        for (uint i; i < users.length; ++i) {
            uint before = _votingRoles.threshold();

            vm.expectEmit();
            emit VoterAdded(users[i]);

            // every third one, we increase the threshold by one as well
            if (i % 3 == 0) {
                vm.expectEmit();
                emit ThresholdUpdated(before, before + 1);
                _votingRoles.addVoterAndUpdateThreshold(users[i], before + 1);
                assertEq(_votingRoles.threshold(), before + 1);
            } else {
                _votingRoles.addVoter(users[i]);
                assertEq(_votingRoles.threshold(), before);
            }
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_votingRoles.isVoter(users[i]), true);
        }
        // test idempotence. We do the same again and verify that nothing fails and everything stays the same.
        for (uint i; i < users.length; ++i) {
            _votingRoles.addVoter(users[i]);
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_votingRoles.isVoter(users[i]), true);
        }

        vm.stopPrank();
    }

    function testRemoveVoter(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        vm.startPrank(address(_votingRoles));
        for (uint i; i < users.length; ++i) {
            vm.expectEmit();
            emit VoterRemoved(users[i]);

            _votingRoles.removeVoter(users[i]);
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_votingRoles.isVoter(users[i]), false);
        }
        // test idempotence. We do the same again and verify that nothing fails and everything stays the same.
        for (uint i; i < users.length; ++i) {
            _votingRoles.removeVoter(users[i]);
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_votingRoles.isVoter(users[i]), false);
        }

        vm.stopPrank();
    }

    // Fail to remove Authorized addresses until threshold is unreachble
    function testRemoveTooManyVoters() public {
        vm.startPrank(address(_votingRoles));
        _votingRoles.removeVoter(COBIE);

        // this call would leave a 1 person list with a threshold of 2
        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__InvalidThreshold
                .selector
        );
        _votingRoles.removeVoter(BOB);

        vm.stopPrank();
    }

    // Fail to remove Authorized addresses until the voterlist is empty
    function testRemoveUntilVoterListEmpty() public {
        vm.startPrank(address(_votingRoles));

        // threshold is 2 out of 3 before this
        _votingRoles.removeVoter(COBIE);

        // regular remove would fail  as it would bring it to
        // 2 out of 1 with the threshold of 2
        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__InvalidThreshold
                .selector
        );
        _votingRoles.removeVoter(BOB);
        assertEq(_votingRoles.threshold(), 2);

        // try to remove again, this time including a reduction
        // of the threshold to 1
        vm.expectEmit();
        emit ThresholdUpdated(2, 1);
        _votingRoles.removeVoterAndUpdateThreshold(BOB, 1);
        assertEq(_votingRoles.threshold(), 1);

        // this call would leave a 1 person list with a threshold of 2
        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__EmptyVoters
                .selector
        );
        _votingRoles.removeVoter(ALBA);

        vm.stopPrank();
    }

    //--------------------------------------------------------------------------
    // TEST: QUORUM

    // Get correct threshold
    function testGetThreshold() public {
        assertEq(_votingRoles.threshold(), DEFAULT_QUORUM);
    }

    // Set a new threshold
    function testMotionSetThreshold() public {
        uint oldThreshold = _votingRoles.threshold();
        uint newThreshold = 3;

        vm.prank(address(_votingRoles));

        vm.expectEmit(true, true, true, true);
        emit ThresholdUpdated(oldThreshold, newThreshold);

        _votingRoles.setThreshold(newThreshold);

        assertEq(_votingRoles.threshold(), newThreshold);
    }

    // Fail to set a threshold that's too damn high or too damn low
    function testSetInvalidThreshold(uint newThreshold) public {
        // Test too high
        vm.assume(newThreshold > _votingRoles.voterCount());

        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__InvalidThreshold
                .selector
        );
        vm.prank(address(_votingRoles));
        _votingRoles.setThreshold(newThreshold);

        // Test too low
        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__InvalidThreshold
                .selector
        );
        vm.prank(address(_votingRoles));
        _votingRoles.setThreshold(1);

        // Test too low with zero
        vm.expectRevert(
            IAUT_EXT_VotingRoles_v1
                .Module__VotingRoleManager__InvalidThreshold
                .selector
        );
        vm.prank(address(_votingRoles));
        _votingRoles.setThreshold(0);
    }

    // Fail to change threshold when not the module itself
    function testUnauthorizedThresholdChange(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        uint _newQ = 1;
        for (uint i; i < users.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    bytes32("onlySelf"),
                    users[i]
                )
            );
            vm.prank(users[i]); // authorized, but not orchestrator
            _votingRoles.setThreshold(_newQ);
        }
    }

    // Change the threshold by going through governance
    function testGovernanceThresholdChange() public {
        uint _newThreshold = 3;

        // 1) Create and approve a vote
        bytes memory _encodedAction =
            abi.encodeWithSignature("setThreshold(uint256)", _newThreshold);
        bytes32 _voteID = speedrunSuccessfulVote(
            address(_votingRoles), _encodedAction, initialVoters
        );

        // 2) The vote gets executed by anybody

        uint _oldThreshold = _votingRoles.threshold();

        vm.expectEmit(true, true, true, true);
        emit ThresholdUpdated(_oldThreshold, _newThreshold);
        emit MotionExecuted(_voteID);

        _votingRoles.executeMotion(_voteID);

        // 3) The orchestrator state has changed
        assertEq(_votingRoles.threshold(), _newThreshold);
    }

    //--------------------------------------------------------------------------
    // TEST: VOTE DURATION

    // Get correct vote duration
    function testGetVoteDuration() public {
        assertEq(_votingRoles.voteDuration(), DEFAULT_DURATION);
    }

    // Set new vote duration
    function testMotionSetVoteDuration() public {
        uint _oldDuration = _votingRoles.voteDuration();
        uint _newDuration = 3 days;

        vm.prank(address(_votingRoles));

        vm.expectEmit(true, true, true, true);
        emit VoteDurationUpdated(_oldDuration, _newDuration);

        _votingRoles.setVotingDuration(_newDuration);

        assertEq(_votingRoles.voteDuration(), _newDuration);
    }

    // Fail to set vote durations out of bounds
    function testMotionSetInvalidVoteDuration() public {
        uint _oldDur = _votingRoles.voteDuration();
        uint _newDur = 3 weeks;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidVotingDuration
                    .selector
            )
        );
        vm.prank(address(_votingRoles));
        _votingRoles.setVotingDuration(_newDur);

        _newDur = 1 hours;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_EXT_VotingRoles_v1
                    .Module__VotingRoleManager__InvalidVotingDuration
                    .selector
            )
        );
        vm.prank(address(_votingRoles));
        _votingRoles.setVotingDuration(_newDur);

        assertEq(_votingRoles.voteDuration(), _oldDur);
    }

    // Set new duration bygoing through governance
    function testGovernanceVoteDurationChange() public {
        // already covered in:
        testVoteExecution();
    }

    // Fail to change vote duration when not the module itself
    function testUnauthorizedGovernanceVoteDurationChange(
        address[] memory users
    ) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        uint _newDuration = 5 days;
        for (uint i; i < users.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    bytes32("onlySelf"),
                    users[i]
                )
            );
            vm.prank(users[i]); // authorized, but not orchestrator
            _votingRoles.setVotingDuration(_newDuration);
        }
    }

    // =========================================================================
    // Test Helper Functions

    function _validateUserList(address[] memory contribs)
        internal
        returns (address[] memory)
    {
        vm.assume(contribs.length != 0);
        vm.assume(contribs.length < 40);
        assumeValidUsers(contribs);

        return contribs;
    }
    // Adapted from orchestrator/helper/TypeSanityHelper.sol

    mapping(address => bool) userCache;

    function assumeValidUsers(address[] memory addrs) public {
        for (uint i; i < addrs.length; ++i) {
            assumeValidUser(addrs[i]);

            // Assume contributor address unique.
            vm.assume(!userCache[addrs[i]]);

            // Add contributor address to cache.
            userCache[addrs[i]] = true;
        }
    }

    function assumeValidUser(address a) public view {
        address[] memory invalids = createInvalidUsers();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(a != invalids[i]);
        }
    }

    function createInvalidUsers() public view returns (address[] memory) {
        address[] memory invalids = new address[](10);

        invalids[0] = address(0);
        invalids[1] = address(_orchestrator);
        invalids[2] = address(_votingRoles);
        invalids[3] = address(_paymentProcessor);
        invalids[4] = address(_token);
        invalids[5] = address(_authorizer);
        invalids[6] = address(this);
        invalids[7] = ALBA;
        invalids[8] = BOB;
        invalids[9] = COBIE;

        return invalids;
    }
    // =========================================================================
}
