// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    SingleVoteGovernor,
    ISingleVoteGovernor
} from "src/modules/governance/SingleVoteGovernor.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Interfaces
import {IProposal} from "src/proposal/IProposal.sol";
import {IModule} from "src/modules/base/IModule.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

contract SingleVoteGovernorTest is Test {
    // SuT
    SingleVoteGovernor _authorizer;

    Proposal _proposal;
    address[] initialVoters;
    address[] currentVoters;

    // Constants and other data structures
    uint internal constant DEFAULT_QUORUM = 2;
    uint internal constant DEFAULT_DURATION = 4 days;
    // For the proposal
    uint internal constant _PROPOSAL_ID = 1;
    // For the metadata
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    // Mocks
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();
    ModuleMock module = new  ModuleMock();
    // Mock users
    // intial authorizd users
    address internal constant ALBA = address(0xa1ba);
    address internal constant BOB = address(0xb0b);
    address internal constant COBIE = address(0xc0b1e);
    ISingleVoteGovernor.Motion _bufMotion;

    function setUp() public {
        // Set up a proposal
        address authImpl = address(new SingleVoteGovernor());
        _authorizer = SingleVoteGovernor(Clones.clone(authImpl));

        address impl = address(new Proposal());
        _proposal = Proposal(Clones.clone(impl));

        address[] memory modules = new address[](1);
        modules[0] = address(module);

        _proposal.init(
            _PROPOSAL_ID,
            address(this),
            _token,
            modules,
            _authorizer,
            _paymentProcessor
        );

        // Initialize the authorizer with 3 users

        initialVoters = new address[](3);
        initialVoters[0] = ALBA;
        initialVoters[1] = BOB;
        initialVoters[2] = COBIE;

        uint _startingThreshold = DEFAULT_QUORUM;
        uint _startingDuration = DEFAULT_DURATION;

        _authorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(initialVoters, _startingThreshold, _startingDuration)
        );

        assertEq(address(_authorizer.proposal()), address(_proposal));
        assertEq(_proposal.isModule(address(_authorizer)), true);

        assertEq(_authorizer.isAuthorized(address(_authorizer)), true);
        assertEq(_authorizer.isVoter(ALBA), true);
        assertEq(_authorizer.isVoter(BOB), true);
        assertEq(_authorizer.isVoter(COBIE), true);

        currentVoters.push(ALBA);
        currentVoters.push(BOB);
        currentVoters.push(COBIE);

        // The deployer may be owner, but not authorized by default
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(_authorizer.isAuthorized(address(_proposal)), false);
        assertEq(_authorizer.isVoter(address(this)), false);
        assertEq(_authorizer.isVoter(address(_proposal)), false);

        assertEq(_authorizer.voterCount(), 3);
    }

    //--------------------------------------------------------------------------
    // Helper functions for common functionalities
    function createVote(address callingUser, address _addr, bytes memory _msg)
        public
        returns (uint)
    {
        vm.prank(callingUser);
        uint _id = _authorizer.createMotion(_addr, _msg);
        return _id;
    }

    function batchAddAuthorized(address[] memory users) public {
        for (uint i; i < users.length; ++i) {
            // We add a new address through governance.
            bytes memory _encodedAction =
                abi.encodeWithSignature("addVoter(address)", users[i]);
            //for ease, we are assuming this is happening before any threshold changes
            uint _voteID = speedrunSuccessfulVote(
                address(_authorizer), _encodedAction, initialVoters
            );
            _authorizer.executeMotion(_voteID);

            currentVoters.push(users[i]);
            assertEq(_authorizer.isVoter(users[i]), true);
        }
    }

    function voteInFavor(address callingUser, uint voteID) public {
        uint8 vote = 0;
        vm.prank(callingUser);
        _authorizer.castVote(voteID, vote);
    }

    function voteAgainst(address callingUser, uint voteID) public {
        uint8 vote = 1;
        vm.prank(callingUser);
        _authorizer.castVote(voteID, vote);
    }

    function voteAbstain(address callingUser, uint voteID) public {
        uint8 vote = 2;
        vm.prank(callingUser);
        _authorizer.castVote(voteID, vote);
    }

    function speedrunSuccessfulVote(
        address _target,
        bytes memory _action,
        address[] memory _voters
    ) public returns (uint) {
        if (_voters.length == 0) {
            revert("Voterlist empty");
        }
        uint _voteID = createVote(_voters[0], _target, _action);

        for (uint i; i < _voters.length; ++i) {
            voteInFavor(_voters[i], _voteID);
        }

        // the voting time passes
        vm.warp(block.timestamp + _authorizer.voteDuration() + 1);

        return _voteID;
    }

    function speedrunRejectedVote(
        address _target,
        bytes memory _action,
        address[] memory _voters
    ) public returns (uint) {
        if (_voters.length == 0) {
            revert("Voterlist empty");
        }
        uint _voteID = createVote(_voters[0], _target, _action);

        for (uint i = 1; i < _authorizer.threshold(); ++i) {
            if (i < _voters.length) {
                voteInFavor(_voters[(i - 1)], _voteID);
            }
        }

        // the voting time passes
        vm.warp(block.timestamp + _authorizer.voteDuration() + 1);

        return _voteID;
    }

    function getMockValidVote() public view returns (address, bytes memory) {
        address _moduleAddress = address(_authorizer);
        bytes memory _msg = abi.encodeWithSignature("setThreshold(uint)", 1);

        return (_moduleAddress, _msg);
    }

    function getFullMotionData(uint voteId)
        internal
        returns (ISingleVoteGovernor.Motion storage)
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
        ) = _authorizer.motions(voteId);

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
                _authorizer.getReceipt(voteId, currentVoters[i]);
        }

        return _bufMotion;
    }

    //--------------------------------------------------------------------------
    // TESTS: INITIALIZATION

    function testInitWithInitialVoters(address[] memory testVoters) public {
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        vm.assume(testVoters.length >= 2);
        _validateUserList(testVoters);

        address authImpl = address(new SingleVoteGovernor());
        SingleVoteGovernor testAuthorizer =
            SingleVoteGovernor(Clones.clone(authImpl));

        //Since the authorizer we are working with is not the default one,
        // we must manually control that the fuzzer doesn't feed us its address
        for (uint i; i < testVoters.length; ++i) {
            vm.assume(testVoters[i] != address(testAuthorizer));
        }

        testAuthorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        assertEq(address(testAuthorizer.proposal()), address(_proposal));

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
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        vm.assume(testVoters.length >= 2);
        vm.assume(position > 0 && position < testVoters.length);

        address authImpl = address(new SingleVoteGovernor());
        SingleVoteGovernor testAuthorizer =
            SingleVoteGovernor(Clones.clone(authImpl));

        _validateUserList(testVoters);

        //Since the authorizer we are working with is not the default one,
        // we must manually control that the fuzzer doesn't feed us its address
        for (uint i; i < testVoters.length; ++i) {
            vm.assume(testVoters[i] != address(testAuthorizer));
        }

        testVoters[position] = testVoters[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__IsAlreadyVoter
                    .selector
            )
        );
        testAuthorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );
    }

    function testReinitFails() public {
        //Create a mock new proposal
        Proposal newProposal = Proposal(Clones.clone(address(new Proposal())));

        address[] memory testVoters = new address[](1);
        testVoters[0] = address(this);

        vm.expectRevert();
        _authorizer.init(
            IProposal(newProposal),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        assertEq(_authorizer.isAuthorized(address(_authorizer)), true);
        assertEq(_authorizer.isVoter(ALBA), true);
        assertEq(_authorizer.isVoter(BOB), true);
        assertEq(_authorizer.isVoter(COBIE), true);
        assertEq(_authorizer.voterCount(), 3);
    }

    function testInitWithInvalidInitialVotersFails() public {
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        address authImpl = address(new SingleVoteGovernor());
        SingleVoteGovernor testAuthorizer =
            SingleVoteGovernor(Clones.clone(authImpl));

        address[] memory testVoters;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__EmptyVoters
                    .selector
            )
        );
        testAuthorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        //test faulty list (zero addresses)
        testVoters = new address[](2);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidVoterAddress
                    .selector
            )
        );
        testAuthorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        testVoters[0] = address(testAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidVoterAddress
                    .selector
            )
        );
        testAuthorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        testVoters[0] = address(_proposal);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidVoterAddress
                    .selector
            )
        );
        testAuthorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(testVoters, DEFAULT_QUORUM, DEFAULT_DURATION)
        );

        assertEq(address(testAuthorizer.proposal()), address(0));
        assertEq(testAuthorizer.voterCount(), 0);
    }

    //--------------------------------------------------------------------------
    // TESTS: VOTE CREATION

    // Create vote correctly
    function testCreateVote() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        for (uint i; i < initialVoters.length; ++i) {
            uint _voteID = createVote(ALBA, _moduleAddress, _msg);

            ISingleVoteGovernor.Motion storage _motion =
                getFullMotionData(_voteID);

            assertEq(_authorizer.motionCount(), (_voteID + 1));
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
            assertEq(_authorizer.isVoter(users[i]), false);
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__CallerNotVoter
                    .selector
            );
            vm.prank(users[i]);
            _authorizer.createMotion(_moduleAddress, _msg);
        }
    }

    function testUnauthorizedVoterAddition(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        for (uint i; i < users.length; ++i) {
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(users[i]); //authorized, but not Module
            _authorizer.addVoter(users[i]);
        }
    }

    function testUnauthorizedVoterRemoval(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        for (uint i; i < users.length; ++i) {
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(users[i]); //authorized, but not Module
            _authorizer.removeVoter(users[i]);
        }
    }

    // Add authorized address and have it create a vote
    function testCreateVoteWithRecentlyAuthorizedAddress(address[] memory users)
        public
    {
        _validateUserList(users);

        batchAddAuthorized(users);

        for (uint i; i < users.length; ++i) {
            assertEq(_authorizer.isVoter(users[i]), true);

            //prank as that address, create a vote and vote on it
            (address _moduleAddress, bytes memory _msg) = getMockValidVote();
            uint _newVote = createVote(users[i], _moduleAddress, _msg);
            voteInFavor(users[i], _newVote);

            //assert that voting worked (also confirms that vote exists)
            assertEq(_authorizer.getReceipt(_newVote, users[i]).hasVoted, true);
        }
    }

    //--------------------------------------------------------------------------
    // TESTS: VOTING

    // Vote in favor at the beginning and at the end of the period
    function testVoteInFavor(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        //create a vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        ISingleVoteGovernor.Motion storage _motion = getFullMotionData(_voteID);
        uint _votesBefore = _motion.forVotes;

        voteInFavor(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; ++i) {
            vm.warp(startTime + i);
            voteInFavor(users[i], _voteID);
        }

        //vote in the last possible moment
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

        //create vote as authorized user
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            // fail to vote as unauthorized address
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__CallerNotVoter
                    .selector
            );
            voteInFavor(users[i], _voteID);
        }
    }

    // Vote against at the beginning and at the end of the period
    function testVoteAgainst(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        //create a vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        ISingleVoteGovernor.Motion storage _motion = getFullMotionData(_voteID);
        uint _votesBefore = _motion.againstVotes;

        voteAgainst(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; ++i) {
            vm.warp(startTime + i);
            voteAgainst(users[i], _voteID);
        }

        //vote in the last possible moment
        vm.warp(startTime + DEFAULT_DURATION);
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
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            // fail to vote as unauthorized address
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__CallerNotVoter
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
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        ISingleVoteGovernor.Motion storage _motion = getFullMotionData(_voteID);
        uint _votesBefore = _motion.abstainVotes;

        voteAbstain(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; ++i) {
            vm.warp(startTime + i);
            voteAbstain(users[i], _voteID);
        }

        //vote in the last possible moment
        vm.warp(startTime + DEFAULT_DURATION);
        voteAbstain(BOB, _voteID);

        ISingleVoteGovernor.Receipt memory _r =
            _authorizer.getReceipt(_voteID, ALBA);
        assertEq(_r.hasVoted, true);
        assertEq(_r.support, 2);

        _r = _authorizer.getReceipt(_voteID, BOB);
        assertEq(_r.hasVoted, true);
        assertEq(_r.support, 2);

        for (uint i; i < users.length; ++i) {
            _r = _authorizer.getReceipt(_voteID, users[i]);
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
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            // fail to vote as unauthorized address
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__CallerNotVoter
                    .selector
            );
            voteAbstain(users[i], _voteID);
        }
    }

    // Fail to vote after vote is closed (testing the three vote variants)
    function testVoteOnExpired(uint[] memory nums) public {
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < nums.length; ++i) {
            vm.assume(nums[i] < 100_000_000_000);
            vm.warp(block.timestamp + DEFAULT_DURATION + 1 + nums[i]);

            // For
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__MotionVotingPhaseClosed
                    .selector
            );

            voteInFavor(ALBA, _voteID);

            // Against
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__MotionVotingPhaseClosed
                    .selector
            );
            voteAgainst(ALBA, _voteID);

            //Abstain
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__MotionVotingPhaseClosed
                    .selector
            );
            voteAbstain(ALBA, _voteID);
        }
    }

    // Fail to vote on an unexisting voteID (testing the three vote variants)
    function testVoteOnUnexistingID(uint160[] memory wrongIDs) public {
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < wrongIDs.length; ++i) {
            vm.assume(wrongIDs[i] > _voteID);
            uint wrongID = wrongIDs[i];

            // For
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidMotionId
                    .selector
            );

            voteInFavor(ALBA, wrongID);

            // Against
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidMotionId
                    .selector
            );

            voteAgainst(ALBA, wrongID);

            //Abstain
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidMotionId
                    .selector
            );
            voteAbstain(ALBA, wrongID);
        }
    }

    // Fail to vote with a different value than the allowed three
    function testCastInvalidVote(uint8 wrongVote) public {
        vm.assume(wrongVote > 2);
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        vm.expectRevert(
            ISingleVoteGovernor
                .Module__SingleVoteGovernor__InvalidSupport
                .selector
        );
        vm.prank(ALBA);
        _authorizer.castVote(_voteID, wrongVote);
    }

    // Fail vote for after already voting (testing the three vote variants)
    function testDoubleVoting(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; ++i) {
            //vote once
            voteAgainst(users[i], _voteID);

            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__AttemptedDoubleVote
                    .selector
            );
            voteInFavor(users[i], _voteID);

            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__AttemptedDoubleVote
                    .selector
            );
            voteAgainst(users[i], _voteID);

            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__AttemptedDoubleVote
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
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );

        // 3) The vote gets executed (by anybody)
        _authorizer.executeMotion(_voteID);

        // 4) The module state has changed
        assertEq(_authorizer.voteDuration(), _newDuration);
    }
    // Fail to execute vote that didn't pass

    function testExecuteInexistentVote(uint wrongId) public {
        //No votes exist yet, everyting should fail
        vm.expectRevert(
            ISingleVoteGovernor
                .Module__SingleVoteGovernor__InvalidMotionId
                .selector
        );
        _authorizer.executeMotion(wrongId);
    }

    // Fail to execute vote that didn't pass
    function testExecuteFailedVote() public {
        (address _moduleAddress, bytes memory _encodedAction) =
            getMockValidVote();

        uint _voteID = speedrunRejectedVote(
            address(_moduleAddress), _encodedAction, initialVoters
        );

        //No prank address needed
        vm.expectRevert(
            ISingleVoteGovernor
                .Module__SingleVoteGovernor__ThresholdNotReached
                .selector
        );
        _authorizer.executeMotion(_voteID);
    }

    //Fail to execute vote while voting is open
    function testExecuteWhileVotingOpen() public {
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        //First, we reach the threshold
        voteInFavor(ALBA, _voteID);
        voteInFavor(BOB, _voteID);

        vm.expectRevert(
            abi.encodePacked(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__MotionInVotingPhase
                    .selector
            )
        );
        _authorizer.executeMotion(_voteID);

        //we wait and try again in the last block of voting time
        vm.warp(block.timestamp + _authorizer.voteDuration());

        vm.expectRevert(
            abi.encodePacked(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__MotionInVotingPhase
                    .selector
            )
        );
        _authorizer.executeMotion(_voteID);
    }

    // Fail to execute an already executed vote
    function testDoubleExecution() public {
        // 1) First we do a normal vote + execution
        uint _newDuration = 3 days;
        bytes memory _encodedAction =
            abi.encodeWithSignature("setVotingDuration(uint256)", _newDuration);

        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );

        // 2) Then the vote gets executed by anybody
        _authorizer.executeMotion(_voteID);

        // 3) the module state has changed
        assertEq(_authorizer.voteDuration(), _newDuration);

        // 4) Now we test that we can't execute again:
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__MotionAlreadyExecuted
                    .selector
            )
        );
        _authorizer.executeMotion(_voteID);
    }

    function testOnlyGovernanceIsAuthorized(address _other) public {
        vm.assume(_other != address(_authorizer));

        vm.expectRevert(IProposal.Proposal__CallerNotAuthorized.selector);
        vm.prank(_other);
        _proposal.executeTx(address(0), "");
    }

    //--------------------------------------------------------------------------
    // TEST: VOTER MANAGEMENT
    function testAddVoters(address[] memory users) public {
        _validateUserList(users);

        vm.startPrank(address(_authorizer));
        for (uint i; i < users.length; ++i) {
            _authorizer.addVoter(users[i]);
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_authorizer.isVoter(users[i]), true);
        }
        //test idempotence. We do the same again and verify that nothing fails and everything stays the same.
        for (uint i; i < users.length; ++i) {
            _authorizer.addVoter(users[i]);
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_authorizer.isVoter(users[i]), true);
        }

        vm.stopPrank();
    }

    function testRemoveVoter(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        vm.startPrank(address(_authorizer));
        for (uint i; i < users.length; ++i) {
            _authorizer.removeVoter(users[i]);
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_authorizer.isVoter(users[i]), false);
        }
        //test idempotence. We do the same again and verify that nothing fails and everything stays the same.
        for (uint i; i < users.length; ++i) {
            _authorizer.removeVoter(users[i]);
        }

        for (uint i; i < users.length; ++i) {
            assertEq(_authorizer.isVoter(users[i]), false);
        }

        vm.stopPrank();
    }

    // Fail to remove Authorized addresses until threshold is unreachble
    function testRemoveTooManyVoters() public {
        assertEq(address(_proposal), address(_authorizer.proposal()));

        vm.startPrank(address(_authorizer));
        _authorizer.removeVoter(COBIE);

        //this call would leave a 1 person list with a threshold of 2
        vm.expectRevert(
            ISingleVoteGovernor
                .Module__SingleVoteGovernor__UnreachableThreshold
                .selector
        );
        _authorizer.removeVoter(BOB);

        vm.stopPrank();
    }

    // Fail to remove Authorized addresses until the voterlist is empty
    function testRemoveUntilVoterListEmpty() public {
        assertEq(address(_proposal), address(_authorizer.proposal()));

        vm.startPrank(address(_authorizer));
        _authorizer.setThreshold(0);

        _authorizer.removeVoter(COBIE);
        _authorizer.removeVoter(BOB);

        //this call would leave a 1 person list with a threshold of 2
        vm.expectRevert(
            ISingleVoteGovernor.Module__SingleVoteGovernor__EmptyVoters.selector
        );
        _authorizer.removeVoter(ALBA);

        vm.stopPrank();
    }

    //--------------------------------------------------------------------------
    // TEST: QUORUM

    // Get correct threshold
    function testGetThreshold() public {
        assertEq(_authorizer.threshold(), DEFAULT_QUORUM);
    }

    // Set a new threshold
    function testMotionSetThreshold() public {
        uint _newQ = 1;

        vm.prank(address(_authorizer));
        _authorizer.setThreshold(_newQ);

        assertEq(_authorizer.threshold(), _newQ);
    }

    // Fail to set a threshold that's too damn high
    function testSetUnreachableThreshold(uint _newQ) public {
        vm.assume(_newQ > _authorizer.voterCount());

        vm.expectRevert(
            ISingleVoteGovernor
                .Module__SingleVoteGovernor__UnreachableThreshold
                .selector
        );
        vm.prank(address(_authorizer));
        _authorizer.setThreshold(_newQ);
    }

    // Fail to change threshold when not the module itself
    function testUnauthorizedThresholdChange(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        uint _newQ = 1;
        for (uint i; i < users.length; ++i) {
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(users[i]); //authorized, but not Proposal
            _authorizer.setThreshold(_newQ);
        }
    }

    //Change the threshold by going through governance
    function testGovernanceThresholdChange() public {
        uint _newThreshold = 1;

        // 1) Create and approve a vote
        bytes memory _encodedAction =
            abi.encodeWithSignature("setThreshold(uint256)", _newThreshold);
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );

        // 2) The vote gets executed by anybody
        _authorizer.executeMotion(_voteID);

        // 3) The proposal state has changed
        assertEq(_authorizer.threshold(), _newThreshold);
    }

    //--------------------------------------------------------------------------
    // TEST: VOTE DURATION

    // Get correct vote duration
    function testGetVoteDuration() public {
        assertEq(_authorizer.voteDuration(), DEFAULT_DURATION);
    }

    // Set new vote duration
    function testMotionSetVoteDuration() public {
        uint _newDur = 3 days;

        vm.prank(address(_authorizer));
        _authorizer.setVotingDuration(_newDur);

        assertEq(_authorizer.voteDuration(), _newDur);
    }

    // Fail to set vote durations out of bounds
    function testMotionSetInvalidVoteDuration() public {
        uint _oldDur = _authorizer.voteDuration();
        uint _newDur = 3 weeks;

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidVotingDuration
                    .selector
            )
        );
        vm.prank(address(_authorizer));
        _authorizer.setVotingDuration(_newDur);

        _newDur = 1 hours;

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidVotingDuration
                    .selector
            )
        );
        vm.prank(address(_authorizer));
        _authorizer.setVotingDuration(_newDur);

        assertEq(_authorizer.voteDuration(), _oldDur);
    }

    //Set new duration bygoing through governance
    function testGovernanceVoteDurationChange() public {
        //already covered in:
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
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(users[i]); //authorized, but not Proposal
            _authorizer.setVotingDuration(_newDuration);
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
    // Adapted from proposal/helper/TypeSanityHelper.sol

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

    function assumeValidUser(address a) public {
        address[] memory invalids = createInvalidUsers();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(a != invalids[i]);
        }
    }

    function createInvalidUsers() public view returns (address[] memory) {
        address[] memory invalids = new address[](10);

        invalids[0] = address(0);
        invalids[1] = address(_proposal);
        invalids[2] = address(_authorizer);
        invalids[3] = address(_paymentProcessor);
        invalids[4] = address(_token);
        invalids[5] = address(module);
        invalids[6] = address(this);
        invalids[7] = ALBA;
        invalids[8] = BOB;
        invalids[9] = COBIE;

        return invalids;
    }
    // =========================================================================
}
