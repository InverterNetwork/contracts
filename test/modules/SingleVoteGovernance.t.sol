// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";


// SuT
import {SingleVoteGovernance, ListAuthorizer} from
    "src/modules/governance/SingleVoteGovernance.sol";

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
    SingleVoteGovernance _authorizer;

    // Mocks
    Proposal _proposal;
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();
    address ALBA = address(0xa1ba);
    address BOB = address(0xb0b);
    address COBIE = address(0xc0b1e);
    address DOBBIE = address(0xd0bb1e);
    address ED = address(0xed);
    address[] initialAuthorized;
    uint constant DEFAULT_QUORUM = 2;
    uint constant DEFAULT_DURATION = 100;

    // Proposal Constants
    uint internal constant _PROPOSAL_ID = 1;

    // Module Constants
    uint internal constant _MAJOR_VERSION = 1;
    string internal constant _GIT_URL = "https://github.com/org/module";

    IModule.Metadata internal _METADATA =
        IModule.Metadata(_MAJOR_VERSION, _GIT_URL);


    function setUp() public {
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
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(_authorizer.isAuthorized(address(_proposal)), true);
        assertEq(_authorizer.getAmountAuthorized(), 3);
    }

    //TODO test call to nonexistent vote ID
    //TODO test proposal tryign to call onauthorized functions through governance

    /// Helper functions for common calls
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

        for (uint i; i < _voters.length; i++) {
            if (i == _authorizer.getQuorum()) {
                break;
            }
            voteInFavor(_voters[i], _voteID);
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

    // ------------ VOTE CREATION TESTS ------------
    // Test create vote correctly
    function testCreateVote() public {
        // check:
        //          Parameters saved right
        //          voteID increased
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        SingleVoteGovernance.Vote memory _res = _authorizer.getVoteByID(_voteID);

        assertEq(_authorizer.getNextVoteID(), (_voteID + 1));
        assertEq(_res.targetAddress, _moduleAddress);
        assertEq(_res.encodedAction, _msg);
    }

    // Test fail create vote as unauthorized address
    function testUnauthorizedVoteCreation() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        // fail if unauthorized user calls the function

        assertEq(_authorizer.isAuthorized(DOBBIE), false);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(DOBBIE); //unauthorized
        _authorizer.createVote(_moduleAddress, _msg);
    }

    // Test add authorized address and have it create vote
    function testCreateVoteWithRecentlyAuthorizedAddress() public {
        //create vote to add authorized address

        bytes memory _encodedAction =
            abi.encodeWithSignature("addToAuthorized(address)", DOBBIE);
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );
        _authorizer.executeVote(_voteID);

        //sucess
        assertEq(_authorizer.isAuthorized(DOBBIE), true);

        //prank as that address and create a vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _newVote = createVote(DOBBIE, _moduleAddress, _msg);
        voteInFavor(DOBBIE, _newVote);

        //assert that voting worked (so vote exists)
        assertEq(_authorizer.hasVoted(DOBBIE, _newVote), true);
    }

    // Test fail create votes with wrong addresses and actions
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

    // ------------ VOTING TESTS ------------
    // Test vote for _proposal
    function testVoteInFavor() public {
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

    // Test vote for _proposal as unauthorized address
    function testVoteInFavorUnauthorized() public {
        //will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail if the external function is called by unauthorized address
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        voteInFavor(DOBBIE, _voteID);
    }

    // Test vote against _proposal
    function testVoteAgainst() public {
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
    // Test vote against _proposal as unauthorized address

    function testVoteAgainstUnauthorized() public {
        //will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail if the external function is called by unauthorized address
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        voteAgainst(DOBBIE, _voteID);
    }

    // Test abstain from _proposal

    function testAbstain() public {
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
    // Test abstain from _proposal as unauthorized address

    function testAbstainUnauthorized() public {
        //will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail if authorized user tries to call the ProposalContext function directly
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        voteAbstain(DOBBIE, _voteID);
    }

    // Test fail vote for _proposal after vote is closed (try 3 variants of vote)
    function testVoteOnExpired() public {
        // try 3 variants, will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__voteExpired
                    .selector,
                _voteID
            )
        );

        voteInFavor(ALBA, _voteID);
        (ALBA, _voteID);

        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__voteExpired
                    .selector,
                _voteID
            )
        );
        voteAgainst(ALBA, _voteID);

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
    // Test fail vote for _proposal after already voting (try 3 variants of vote)

    function testDoubleVoting() public {
        //try 3 variants, will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        voteAgainst(ALBA, _voteID);

        //The following calls shouldn't revert, but shouldn't change state either
        // TODO check event emission

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

    // ------------ VOTE EXECUTION TESTS ------------
    // Test executing vote that passed
    function testVoteExecution() public {
        // Here we will test a "standard" execution process to change the vote Duration. The process will be:

        uint _newDuration = 5000;

        // somebody creates a vote
        bytes memory _encodedAction =
            abi.encodeWithSignature("changeVoteDuration(uint256)", _newDuration);

        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        // the vote gets executed by anybody
        _authorizer.executeVote(_voteID);

        // the proposal state has changed
        assertEq(_authorizer.getVoteDuration(), _newDuration);
    }

    // Test fail execute vote that didn't pass
    function testExecuteFailedVote() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        voteInFavor(ALBA, _voteID);
        (ALBA, _voteID);

        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance__quorumNotReached
                    .selector,
                _voteID
            )
        );

        //no prank address needed
        _authorizer.executeVote(_voteID);
    }
    // Test fail execute vote while voting is open

    function testExecuteWhileVotingOpen() public {
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
        //no prank address needed
        _authorizer.executeVote(_voteID);

        vm.stopPrank();
    }
    // Test fail execute an already executed vote

    function testDoubleExecution() public {
        // First we do a normal vote + execution
        uint _newDuration = 5000;

        // somebody creates a vote

        bytes memory _encodedAction =
            abi.encodeWithSignature("changeVoteDuration(uint256)", _newDuration);
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        // the vote gets executed by anybody
        _authorizer.executeVote(_voteID);

        // the proposal state has changed
        assertEq(_authorizer.getVoteDuration(), _newDuration);

        // now we test we can't execute again:
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

    // ------------ QUORUM TESTS ------------
    // Test get correct quorum
    function testGetQuorum() public {
        assertEq(_authorizer.getQuorum(), DEFAULT_QUORUM);
    }

    // Test set a new quorum
    function testSetQuorum() public {
        uint _newQ = 1;

        vm.prank(address(_proposal));
        _authorizer.changeQuorum(_newQ);

        assertEq(_authorizer.getQuorum(), _newQ);
    }

    // Test fail set a quorum that's too damn high
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
    // Test fail set quorum to zero

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
    // Test fail remove Authorized addresses until quorum is unreachble

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
        //vm.prank(address(_proposal));
        _authorizer.removeFromAuthorized(BOB);

        vm.stopPrank();
    }
    // Test fail quorum change as unauthorized address (not _proposal)

    function testUnauthorizedQuorumChange() public {
        uint _newQ = 1;

        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(ALBA); //authorized, but not Proposal
        _authorizer.changeQuorum(_newQ);
    }

    //      -> About this: Quorum changes can only be done by the _proposal, which means that any quorum change must pass through governance. This guarantees that any previous vote with the old quorum will have finished before it changes.
    // @note: Make sure the above happens by mocking a whole voting process (blocked by the first voting exec test)
    function testGovernanceQuorumChangeTiming() public {
        //TODO not needed anymore, we now store the required quorum on creation.
    }

    //Test that the change thorugh governance works
    function testGovernanceQuorumChange() public {

        uint _newQuorum = 1;

        // somebody creates a vote

        bytes memory _encodedAction =
            abi.encodeWithSignature("changeQuorum(uint256)", _newQuorum);
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialAuthorized
        );

        // the vote gets executed by anybody
        _authorizer.executeVote(_voteID);

        // the proposal state has changed
        assertEq(_authorizer.getQuorum(), 1);
    }

    // ------------ VOTE DURATION TESTS ------------
    // Test get correct vote duration
    function testGetVoteDuration() public {
        assertEq(_authorizer.getVoteDuration(), DEFAULT_DURATION);
    }

    // Test set new vote duration
    function testSetVoteDuration() public {
        uint _newDur = 1234;

        vm.prank(address(_proposal));
        _authorizer.changeVoteDuration(_newDur);

        assertEq(_authorizer.getVoteDuration(), _newDur);
    }

    //Test that the change through governance works
    function testGovernanceVoteDurationChange() public {
        //covered in:
        testVoteExecution();
    }
}
