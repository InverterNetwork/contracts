// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
import {ContributorManager} from "src/proposal/base/ContributorManager.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";
import {SingleVoteGovernance} from
    "src/modules/governance/SingleVoteGovernance.sol";

// Interfaces
import {IAuthorizer} from "src/modules/IAuthorizer.sol";
import {IProposal} from "src/proposal/IProposal.sol";
import {IModule} from "src/modules/base/IModule.sol";

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
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
    uint8 constant DEFAULT_QUORUM = 2;
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

        address[] memory initialAuthorized = new address[](3);
        initialAuthorized[0] = ALBA;
        initialAuthorized[1] = BOB;
        initialAuthorized[2] = COBIE;

        uint8 _startingQuorum = DEFAULT_QUORUM;
        uint _startingDuration = DEFAULT_DURATION;

        _authorizer.initialize(
            IProposal(_proposal),
            initialAuthorized,
            _startingQuorum,
            _startingDuration,
            _METADATA
        );

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.isAuthorized(BOB), true);
        assertEq(_authorizer.isAuthorized(COBIE), true);
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(_authorizer.getAmountAuthorized(), 3);
    }

    /// Helper function. Impersonates the _proposal to directly create a vote
    function createVote(address callingUser, address _addr, bytes memory _msg)
        public
        returns (uint)
    {
        uint _id = _authorizer.getNextVoteID();
        vm.prank(callingUser);
        _authorizer.createVote(_addr, _msg);
        return _id;
    }

    function voteInFavor(address callingUser, uint voteID)
        public
    {
        vm.prank(callingUser);
        _authorizer.voteInFavor(voteID);
    }
    function voteAgainst(address callingUser, uint voteID)
        public
    {
        vm.prank(callingUser);
        _authorizer.voteAgainst(voteID);
    }
        
    function voteAbstain(address callingUser, uint voteID)
        public
    {
        vm.prank(callingUser);
        _authorizer.voteAbstain(voteID);
    }

    function getMockValidVote() public view returns (address, bytes memory) {
        address _moduleAddress = address(_authorizer);
        bytes memory _msg =
            abi.encodeWithSignature("__Governance_changeQuorum(uint8)", 1);

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

        // TODO: test normal flow (executeTxFromModule) too !!!
    }

    // Test fail create vote as unauthorized address
    function testUnauthorizedVoteCreation() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        // fail if the ProposalContext function is called directly
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(ALBA); //authorized, but not Proposal
        _authorizer.__Governance_createVote(_moduleAddress, _msg);

        // fail if the external function is called
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(DOBBIE); //Neither Proposal nor authorized
        _authorizer.createVote(_moduleAddress, _msg);
    }

    // Test add authorized address and have it create vote
    function testCreateVoteWithRecentlyAuthorizedAddress() public {
        // TODO only testable in the normal flow (executeTxFromModule)
    }

    // Test fail create votes with wrong addresses and actions
    function testCreateWithInvalidVoteParamters() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        vm.expectRevert(
            abi.encodeWithSelector(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance_invalidModuleAddress
                    .selector,
                0x42
            )
        );
        vm.prank(address(_proposal));
        _authorizer.__Governance_createVote(address(0x42), _msg);

        vm.expectRevert(
            abi.encodeWithSelector(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance_invalidEncodedAction
                    .selector,
                ""
            )
        );
        vm.prank(address(_proposal));
        _authorizer.__Governance_createVote(_moduleAddress, "");
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

        // TODO: test normal flow (executeTxFromModule) too !!!
    }

    // Test vote for _proposal as unauthorized address
    function testVoteInFavorUnauthorized() public {
        //will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail if the ProposalContext function is called directly
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(ALBA); //authorized, but not Proposal
        _authorizer.__Governance_voteInFavor(ALBA, _voteID);

        // fail if the external function is called
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(DOBBIE); //Neither Proposal nor authorized
        _authorizer.voteInFavor(_voteID);
    }

    // Test vote against _proposal
    function testVoteAgainst() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        uint _votesBefore = _authorizer.getVoteByID(_voteID).nay;

        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAgainst(ALBA, _voteID);

        //vote in the last possible moment
        vm.warp(block.timestamp + DEFAULT_DURATION);
        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAgainst(BOB, _voteID);

        assert(_authorizer.hasVoted(ALBA, _voteID) == true);
        assert(_authorizer.hasVoted(BOB, _voteID) == true);
        assert(_authorizer.getVoteByID(_voteID).nay == (_votesBefore + 2));
        // TODO: test normal flow (executeTxFromModule) too !!!
    }
    // Test vote against _proposal as unauthorized address

    function testVoteAgainstUnauthorized() public {
        //will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail if the ProposalContext function is called directly
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(ALBA); //authorized, but not Proposal
        _authorizer.__Governance_voteAgainst(ALBA, _voteID);

        // fail if the external function is called
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(DOBBIE); //Neither Proposal nor authorized
        _authorizer.voteInFavor(_voteID);
    }
    // Test abstain from _proposal

    function testAbstain() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        uint _votesBefore = _authorizer.getVoteByID(_voteID).abstain;

        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAbstain(ALBA, _voteID);

        //vote in the last possible moment
        vm.warp(block.timestamp + DEFAULT_DURATION);
        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAbstain(BOB, _voteID);

        assert(_authorizer.hasVoted(ALBA, _voteID) == true);
        assert(_authorizer.hasVoted(BOB, _voteID) == true);
        assert(_authorizer.getVoteByID(_voteID).abstain == (_votesBefore + 2));

        // TODO: test normal flow (executeTxFromModule) too !!!
    }
    // Test abstain from _proposal as unauthorized address

    function testAbstainUnauthorized() public {
        //will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        // fail if the ProposalContext function is called directly
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(ALBA); //authorized, but not Proposal
        _authorizer.__Governance_voteAbstain(ALBA, _voteID);

        // fail if the external function is called
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(DOBBIE); //Neither Proposal nor authorized
        _authorizer.voteAbstain(_voteID);
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
                    .Module__SingleVoteGovernance_voteExpired
                    .selector,
                _voteID
            )
        );

        voteInFavor(ALBA, _voteID);(ALBA, _voteID);

        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance_voteExpired
                    .selector,
                _voteID
            )
        );
        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAgainst(ALBA, _voteID);

        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance_voteExpired
                    .selector,
                _voteID
            )
        );
        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAbstain(ALBA, _voteID);
    }
    // Test fail vote for _proposal after already voting (try 3 variants of vote)

    function testDoubleVoting() public {
        //try 3 variants, will fail
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);
        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAgainst(ALBA, _voteID);

        //The following calls shouldn't revert, but shouldn't change state either
        // TODO check event emission

        uint _ayeBefore = _authorizer.getVoteByID(_voteID).aye;

        voteInFavor(ALBA, _voteID);(ALBA, _voteID);
        assertEq(_ayeBefore, _authorizer.getVoteByID(_voteID).aye);

        uint _nayBefore = _authorizer.getVoteByID(_voteID).nay;
        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAgainst(ALBA, _voteID);
        assertEq(_nayBefore, _authorizer.getVoteByID(_voteID).nay);

        uint _abstainBefore = _authorizer.getVoteByID(_voteID).abstain;
        vm.prank(address(_proposal));
        _authorizer.__Governance_voteAbstain(ALBA, _voteID);
        assertEq(_abstainBefore, _authorizer.getVoteByID(_voteID).abstain);
    }

    // ------------ VOTE EXECUTION TESTS ------------
    // Test executing vote that passed
    function testVoteExecution() public {
        // TODO: Probably to be movedto E2E testing?
    }

    // Test fail execute vote that didn't pass
    function testExecuteFailedVote() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        uint _voteID = createVote(ALBA, _moduleAddress, _msg);


        voteInFavor(ALBA, _voteID);(ALBA, _voteID);

        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        vm.expectRevert(
            abi.encodePacked(
                SingleVoteGovernance
                    .Module__SingleVoteGovernance_quorumNotReached
                    .selector,
                _voteID
            )
        );
        vm.prank(address(_proposal));
        _authorizer.__Governance_executeVote(_voteID);
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
                    .Module__SingleVoteGovernance_voteStillActive
                    .selector,
                _voteID
            )
        );
        vm.startPrank(address(_proposal));
        _authorizer.__Governance_executeVote(_voteID);

        vm.stopPrank();
    }
    // Test fail execute an already executed vote

    function testDoubleExecution() public {
        //TODO Blocked by execution test
    }

    // ------------ QUORUM TESTS ------------
    // Test get correct quorum
    function testGetQuorum() public {
        assertEq(_authorizer.getRequiredQuorum(), DEFAULT_QUORUM);
    }

    // Test set a new quorum
    function testSetQuorum() public {
        uint8 _newQ = 1;

        vm.prank(address(_proposal));
        _authorizer.__Governance_changeQuorum(_newQ);

        assertEq(_authorizer.getRequiredQuorum(), _newQ);
    }

    // Test fail set a quorum that's too damn high
    function testSetUnreachableQuorum() public {
        uint8 _newQ = uint8(_authorizer.getAmountAuthorized() + 1);

        vm.expectRevert(
            SingleVoteGovernance
                .Module__SingleVoteGovernance_quorumUnreachable
                .selector
        );
        vm.prank(address(_proposal));
        _authorizer.__Governance_changeQuorum(_newQ);
    }
    // Test fail set quorum to zero

    function testSetZeroQuorum() public {
        uint8 _newQ = 0;

        vm.expectRevert(
            SingleVoteGovernance
                .Module__SingleVoteGovernance_quorumIsZero
                .selector
        );
        vm.prank(address(_proposal));
        _authorizer.__Governance_changeQuorum(_newQ);
    }
    // Test fail remove Authorized addresses until quorum is unreachble

    function testRemoveTooManyAuthorized() public {
        vm.prank(address(_proposal));
        _authorizer.__ListAuthorizer_removeFromAuthorized(COBIE);

        //this call would leave a 1 person list with 2 quorum
        vm.expectRevert(
            SingleVoteGovernance
                .Module__SingleVoteGovernance_quorumUnreachable
                .selector
        );
        vm.prank(address(_proposal));
        _authorizer.__ListAuthorizer_removeFromAuthorized(BOB);
    }
    // Test fail quorum change as unauthorized address (not _proposal)

    function testUnauthorizedQuorumChange() public {
        uint8 _newQ = 1;

        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(ALBA); //authorized, but not Proposal
        _authorizer.__Governance_changeQuorum(_newQ);
    }

    //      -> About this: Quorum changes can only be done by the _proposal, which means that any quorum change must pass through governance. This guarantees that any previous vote with the old quorum will have finished before it changes.
    // @note: Make sure the above happens by mocking a whole voting process (blocked by the first voting exec test)
    function testGovernanceQuorumChangeTiming() public {
        //TODO blocked by execution test
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
        _authorizer.__Governance_changeVoteDuration(_newDur);

        assertEq(_authorizer.getVoteDuration(), _newDur);
    }
}
