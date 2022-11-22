// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    SingleVoteGovernance,
    ListAuthorizer
} from "src/modules/governance/SingleVoteGovernance.sol";

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

contract SingleVoteGovernanceTest is Test {
    //TODO Test proposal tryign to call onauthorized functions through governance

    // SuT
    SingleVoteGovernance _authorizer;

    Proposal _proposal;
    address[] initialAuthorized;

    // Constants and other data structures
    uint internal constant DEFAULT_QUORUM = 2;
    uint internal constant DEFAULT_DURATION = 100;
    // For the proposal
    uint internal constant _PROPOSAL_ID = 1;
    // For the metadata
    uint internal constant _MAJOR_VERSION = 1;
    string internal constant _GIT_URL = "https://github.com/org/module";
    IModule.Metadata internal _METADATA =
        IModule.Metadata(_MAJOR_VERSION, _GIT_URL);

    // Mocks
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();
    // Mock users
    address internal constant ALBA = address(0xa1ba);
    address internal constant BOB = address(0xb0b);
    address internal constant COBIE = address(0xc0b1e);
    address internal constant DOBBIE = address(0xd0bb1e);
    address internal constant ED = address(0xed);

    function setUp() public {
        // Set up a proposal
        address authImpl = address(new SingleVoteGovernance());
        _authorizer = SingleVoteGovernance(Clones.clone(authImpl));

        address impl = address(new Proposal());
        _proposal = Proposal(Clones.clone(impl));

        ModuleMock module = new  ModuleMock();
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

        initialAuthorized = new address[](3);
        initialAuthorized[0] = ALBA;
        initialAuthorized[1] = BOB;
        initialAuthorized[2] = COBIE;

        uint _startingQuorum = DEFAULT_QUORUM;
        uint _startingDuration = DEFAULT_DURATION;

        _authorizer.initialize(
            IProposal(_proposal),
            initialAuthorized,
            _startingQuorum,
            _startingDuration,
            _METADATA
        );

        assertEq(address(_authorizer.proposal()), address(_proposal));
        assertEq(_proposal.isModule(address(_authorizer)), true);

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.isAuthorized(BOB), true);
        assertEq(_authorizer.isAuthorized(COBIE), true);

        // The deployer is owner, but not authorized by default
        assertEq(_authorizer.isAuthorized(address(this)), false);
        // The proposal itself is authorized by default to allow for callbacks...
        assertEq(_authorizer.isAuthorized(address(_proposal)), true);
        // ...but excluded from the list of "authorized addresses"
        assertEq(_authorizer.getAmountAuthorized(), 3);
    }

    //--------------------------------------------------------------------------
    // Helper functions for common functionalities
    function createVote(address callingUser, address _addr, bytes memory _msg)
        public
        returns (uint)
    {
        vm.prank(callingUser);
        uint _id = _authorizer.createVote(_addr, _msg);
        return _id;
    }

    function voteInFavor(address callingUser, uint voteID) public {
        vm.prank(callingUser);
        _authorizer.voteInFavor(voteID);
    }

    function voteAgainst(address callingUser, uint voteID) public {
        vm.prank(callingUser);
        _authorizer.voteAgainst(voteID);
    }

    function voteAbstain(address callingUser, uint voteID) public {
        vm.prank(callingUser);
        _authorizer.voteAbstain(voteID);
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

        for (uint i; i < _voters.length; i++) {
            voteInFavor(_voters[i], _voteID);
        }

        // the voting time passes
        vm.warp(block.timestamp + _authorizer.getVoteDuration() + 1);

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

        for (uint i = 1; i < _authorizer.getQuorum(); i++) {
            if (i < _voters.length) {
                voteInFavor(_voters[(i - 1)], _voteID);
            }
        }

        // the voting time passes
        vm.warp(block.timestamp + _authorizer.getVoteDuration() + 1);

        return _voteID;
    }

    function getMockValidVote() public view returns (address, bytes memory) {
        address _moduleAddress = address(_authorizer);
        bytes memory _msg =
            abi.encodeWithSignature("__Governance_changeQuorum(uint)", 1);

        return (_moduleAddress, _msg);
    }

    //--------------------------------------------------------------------------
    // TESTS: VOTE CREATION

    // Create vote correctly
    function testCreateVote() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        SingleVoteGovernance.Vote memory _res = _authorizer.getVoteByID(_voteID);

        assertEq(_authorizer.getNextVoteID(), (_voteID + 1));
        assertEq(_res.targetAddress, _moduleAddress);
        assertEq(_res.encodedAction, _msg);
    }

    // Fail to create a vote as unauthorized address
    function testUnauthorizedVoteCreation() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        assertEq(_authorizer.isAuthorized(DOBBIE), false);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(DOBBIE);
        _authorizer.createVote(_moduleAddress, _msg);
    }

    // Add authorized address and have it create a vote
    function testCreateVoteWithRecentlyAuthorizedAddress() public {
        // We add a new address through governance.
        bytes memory _encodedAction =
            abi.encodeWithSignature("addToAuthorized(address)", DOBBIE);
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );
        _authorizer.executeVote(_voteID);

        //sucess
        assertEq(_authorizer.isAuthorized(DOBBIE), true);

        //prank as that address, create a vote and vote on it
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _newVote = createVote(DOBBIE, _moduleAddress, _msg);
        voteInFavor(DOBBIE, _newVote);

        //assert that voting worked (also confirms that vote exists)
        assertEq(_authorizer.hasVoted(DOBBIE, _newVote), true);
    }

    // Fail to create votes with wrong addresses and actions
    function testCreateWithInvalidVoteParamters() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        vm.expectRevert(
            abi.encodeWithSelector(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__invalidModuleAddress
                    .selector,
                0x42
            )
        );
        vm.prank(ALBA);
        _authorizer.createVote(address(0x42), _msg);

        vm.expectRevert(
            abi.encodeWithSelector(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__invalidEncodedAction
                    .selector,
                ""
            )
        );
        vm.prank(ALBA);
        _authorizer.createVote(_moduleAddress, "");
    }

    //--------------------------------------------------------------------------
    // TESTS: VOTING

    // Vote in favor at the beginning and at the end of the period
    function testVoteInFavor() public {
        //create a vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        uint _votesBefore = _authorizer.getVoteByID(_voteID).aye;

        voteInFavor(ALBA, _voteID);

        //vote in the last possible moment
        vm.warp(block.timestamp + DEFAULT_DURATION);

        voteInFavor(BOB, _voteID);

        assert(_authorizer.hasVoted(ALBA, _voteID) == true);
        assert(_authorizer.hasVoted(BOB, _voteID) == true);
        assert(_authorizer.getVoteByID(_voteID).aye == (_votesBefore + 2));
    }

    // Fail to vote in favor as unauthorized address
    function testVoteInFavorUnauthorized() public {
        //create vote as authorized user
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail to vote as unauthorized address
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        voteInFavor(DOBBIE, _voteID);
    }

    // Vote against at the beginning and at the end of the period
    function testVoteAgainst() public {
        //create a vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        uint _votesBefore = _authorizer.getVoteByID(_voteID).nay;

        voteAgainst(ALBA, _voteID);

        //vote in the last possible moment
        vm.warp(block.timestamp + DEFAULT_DURATION);
        voteAgainst(BOB, _voteID);

        assert(_authorizer.hasVoted(ALBA, _voteID) == true);
        assert(_authorizer.hasVoted(BOB, _voteID) == true);
        assert(_authorizer.getVoteByID(_voteID).nay == (_votesBefore + 2));
    }

    // Fail to vote against as unauthorized address
    function testVoteAgainstUnauthorized() public {
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail to vote as unauthorized address
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        voteAgainst(DOBBIE, _voteID);
    }

    // Vote abstain at the beginning and at the end of the period
    function testAbstain() public {
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        uint _votesBefore = _authorizer.getVoteByID(_voteID).abstain;

        voteAbstain(ALBA, _voteID);

        //vote in the last possible moment
        vm.warp(block.timestamp + DEFAULT_DURATION);
        voteAbstain(BOB, _voteID);

        assert(_authorizer.hasVoted(ALBA, _voteID) == true);
        assert(_authorizer.hasVoted(BOB, _voteID) == true);
        assert(_authorizer.getVoteByID(_voteID).abstain == (_votesBefore + 2));
    }

    // Fail to vote abstain as unauthorized address
    function testAbstainUnauthorized() public {
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail to vote as unauthorized address
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        voteAbstain(DOBBIE, _voteID);
    }

    // Fail to vote after vote is closed (testing the three vote variants)
    function testVoteOnExpired() public {
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        // For
        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__voteExpired
                    .selector,
                _voteID
            )
        );

        voteInFavor(ALBA, _voteID);

        // Against
        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__voteExpired
                    .selector,
                _voteID
            )
        );
        voteAgainst(ALBA, _voteID);

        //Abstain
        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__voteExpired
                    .selector,
                _voteID
            )
        );
        voteAbstain(ALBA, _voteID);
    }

    // Fail to vote on an unexisting voteID (testing the three vote variants)
    function testVoteOnUnexistingID() public {
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        uint wrongID = _voteID + 1;

        // For
        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__nonexistentVoteId
                    .selector,
                wrongID
            )
        );

        voteInFavor(ALBA, wrongID);

        // Against
        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__nonexistentVoteId
                    .selector,
                wrongID
            )
        );
        voteAgainst(ALBA, wrongID);

        //Abstain
        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__nonexistentVoteId
                    .selector,
                wrongID
            )
        );
        voteAbstain(ALBA, wrongID);
    }

    // Fail vote for after already voting (testing the three vote variants)
    function testDoubleVoting() public {
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        //vote once
        voteAgainst(ALBA, _voteID);

        //The following calls shouldn't revert, but shouldn't change state either
        uint _ayeBefore = _authorizer.getVoteByID(_voteID).aye;
        voteInFavor(ALBA, _voteID);
        assertEq(_ayeBefore, _authorizer.getVoteByID(_voteID).aye);

        uint _nayBefore = _authorizer.getVoteByID(_voteID).nay;
        voteAgainst(ALBA, _voteID);
        assertEq(_nayBefore, _authorizer.getVoteByID(_voteID).nay);

        uint _abstainBefore = _authorizer.getVoteByID(_voteID).abstain;
        voteAbstain(ALBA, _voteID);
        assertEq(_abstainBefore, _authorizer.getVoteByID(_voteID).abstain);
    }

    //--------------------------------------------------------------------------
    // TEST: VOTE EXECUTION

    // Executing a vote that passed
    function testVoteExecution() public {
        // Here we will test a "standard" execution process to change the vote Duration. The process will be:

        // 1) Somebody creates a vote
        uint _newDuration = 1234;
        bytes memory _encodedAction =
            abi.encodeWithSignature("changeVoteDuration(uint256)", _newDuration);

        // 2) The vote passes
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        // 3) The vote gets executed (by anybody)
        _authorizer.executeVote(_voteID);

        // 4) The proposal state has changed
        assertEq(_authorizer.getVoteDuration(), _newDuration);
    }

    // Fail to execute vote that didn't pass
    function testExecuteFailedVote() public {
        (address _moduleAddress, bytes memory _encodedAction) =
            getMockValidVote();

        uint _voteID = speedrunRejectedVote(
            address(_moduleAddress), _encodedAction, initialAuthorized
        );

        //No prank address needed
        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__quorumNotReached
                    .selector,
                _voteID
            )
        );
        _authorizer.executeVote(_voteID);
    }

    //Fail to execute vote while voting is open
    function testExecuteWhileVotingOpen() public {
        // create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        //First, we reach quorum
        voteInFavor(ALBA, _voteID);
        voteInFavor(BOB, _voteID);

        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__voteStillActive
                    .selector,
                _voteID
            )
        );
        _authorizer.executeVote(_voteID);
    }

    // Fail to execute an already executed vote
    function testDoubleExecution() public {
        // 1) First we do a normal vote + execution
        uint _newDuration = 5000;
        bytes memory _encodedAction =
            abi.encodeWithSignature("changeVoteDuration(uint256)", _newDuration);

        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        // 2) Then the vote gets executed by anybody
        _authorizer.executeVote(_voteID);

        // 3) the proposal state has changed
        assertEq(_authorizer.getVoteDuration(), _newDuration);

        // 4) Now we test that we can't execute again:
        vm.expectRevert(
            abi.encodeWithSelector(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__voteAlreadyExecuted
                    .selector,
                _voteID
            )
        );
        _authorizer.executeVote(_voteID);
    }

    // Fail to execute governance functions through governance-approved callbacks (testing all 4 limited functions)
    function testGovernanceLoopFails() public {
        // 1) Create (but don't execute) a set of passed votes which could act on future governance decisions

        uint _futureVoteID = (_authorizer.getNextVoteID() + 3);

        bytes memory _encodedAction =
            abi.encodeWithSignature("voteInFavor(uint256)", _futureVoteID);

        uint attackID_1 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        _encodedAction =
            abi.encodeWithSignature("voteAgainst(uint256)", _futureVoteID);

        uint attackID_2 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        _encodedAction =
            abi.encodeWithSignature("voteAbstain(uint256)", _futureVoteID);

        uint attackID_3 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        //create a vote susceptible to be attacked
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _targetVoteID = createVote(ALBA, _moduleAddress, _msg);
        assertEq(_futureVoteID, _targetVoteID);

        // All execution attempts should fail
        vm.expectRevert(
            abi.encodeWithSelector(IModule.Module__CallerNotAuthorized.selector)
        );
        _authorizer.executeVote(attackID_1);

        vm.expectRevert(
            abi.encodeWithSelector(IModule.Module__CallerNotAuthorized.selector)
        );
        _authorizer.executeVote(attackID_2);

        vm.expectRevert(
            abi.encodeWithSelector(IModule.Module__CallerNotAuthorized.selector)
        );
        _authorizer.executeVote(attackID_3);

        //Also check that vote creation isn't allowed this way
        (_moduleAddress, _msg) = getMockValidVote();
        _encodedAction = abi.encodeWithSignature(
            "createVote(address,bytes)", _moduleAddress, _msg
        );
        uint attackID_4 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule.Module__CallerNotAuthorized.selector
            )
        );
        _authorizer.executeVote(attackID_4);
    }

    //--------------------------------------------------------------------------
    // TEST: QUORUM

    // Get correct quorum
    function testGetQuorum() public {
        assertEq(_authorizer.getQuorum(), DEFAULT_QUORUM);
    }

    // Set a new quorum
    function testSetQuorum() public {
        uint _newQ = 1;

        vm.prank(address(_proposal));
        _authorizer.changeQuorum(_newQ);

        assertEq(_authorizer.getQuorum(), _newQ);
    }

    // Fail to set a quorum that's too damn high
    function testSetUnreachableQuorum() public {
        uint _newQ = uint(_authorizer.getAmountAuthorized() + 1);

        vm.expectRevert(
            SingleVoteGovernance
                .Module__SingleVoteGovernance__quorumUnreachable
                .selector
        );
        vm.prank(address(_proposal));
        _authorizer.changeQuorum(_newQ);
    }

    // Fail to set quorum to zero
    function testSetZeroQuorum() public {
        uint _newQ = 0;

        vm.expectRevert(
            SingleVoteGovernance
                .Module__SingleVoteGovernance__quorumCannotBeZero
                .selector
        );
        vm.prank(address(_proposal));
        _authorizer.changeQuorum(_newQ);
    }

    // Fail to remove Authorized addresses until quorum is unreachble
    function testRemoveTooManyAuthorized() public {
        assertEq(address(_proposal), address(_authorizer.proposal()));

        vm.startPrank(address(_proposal));
        _authorizer.removeFromAuthorized(COBIE);

        //this call would leave a 1 person list with 2 quorum
        vm.expectRevert(
            SingleVoteGovernance
                .Module__SingleVoteGovernance__quorumUnreachable
                .selector
        );
        _authorizer.removeFromAuthorized(BOB);

        vm.stopPrank();
    }

    // Fail to change quorum whrn not the proposal
    function testUnauthorizedQuorumChange() public {
        uint _newQ = 1;

        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(ALBA); //authorized, but not Proposal
        _authorizer.changeQuorum(_newQ);
    }

    //Change the quorum by going through governance
    function testGovernanceQuorumChange() public {
        uint _newQuorum = 1;

        // 1) Create and approve a vote
        bytes memory _encodedAction =
            abi.encodeWithSignature("changeQuorum(uint256)", _newQuorum);
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        // 2) The vote gets executed by anybody
        _authorizer.executeVote(_voteID);

        // 3) The proposal state has changed
        assertEq(_authorizer.getQuorum(), 1);
    }

    //--------------------------------------------------------------------------
    // TEST: VOTE DURATION

    // Get correct vote duration
    function testGetVoteDuration() public {
        assertEq(_authorizer.getVoteDuration(), DEFAULT_DURATION);
    }

    // Set new vote duration
    function testSetVoteDuration() public {
        uint _newDur = 1234;

        vm.prank(address(_proposal));
        _authorizer.changeVoteDuration(_newDur);

        assertEq(_authorizer.getVoteDuration(), _newDur);
    }

    //Set new duration bygoing through governance
    function testGovernanceVoteDurationChange() public {
        //already covered in:
        testVoteExecution();
    }
}
