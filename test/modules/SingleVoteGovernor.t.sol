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
    ISingleVoteGovernor.Proposal _bufProp;

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

        uint _startingQuorum = DEFAULT_QUORUM;
        uint _startingDuration = DEFAULT_DURATION;

        _authorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(initialVoters, _startingQuorum, _startingDuration)
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
        uint _id = _authorizer.createProposal(_addr, _msg);
        return _id;
    }

    function batchAddAuthorized(address[] memory users) public {
        for (uint i; i < users.length; i++) {
            // We add a new address through governance.
            bytes memory _encodedAction =
                abi.encodeWithSignature("addVoter(address)", users[i]);
            //for ease, we are assuming this is happening before any quorum changes
            uint _voteID = speedrunSuccessfulVote(
                address(_authorizer), _encodedAction, initialVoters
            );
            _authorizer.executeProposal(_voteID);

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

        for (uint i; i < _voters.length; i++) {
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

        for (uint i = 1; i < _authorizer.quorum(); i++) {
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
        bytes memory _msg = abi.encodeWithSignature("setQuorum(uint)", 1);

        return (_moduleAddress, _msg);
    }

    function getFullProposalData(uint voteId)
        internal
        returns (ISingleVoteGovernor.Proposal storage)
    {
        (
            address _addr,
            bytes memory _act,
            uint _start,
            uint _end,
            uint _quorum,
            uint _for,
            uint _against,
            uint _abstain,
            uint _excAt,
            bool _excRes,
            bytes memory _excData
        ) = _authorizer.proposals(voteId);

        _bufProp.target = _addr;
        _bufProp.action = _act;
        _bufProp.startTimestamp = _start;
        _bufProp.endTimestamp = _end;
        _bufProp.requiredQuorum = _quorum;
        _bufProp.forVotes = _for;
        _bufProp.againstVotes = _against;
        _bufProp.abstainVotes = _abstain;
        _bufProp.executedAt = _excAt;
        _bufProp.executionResult = _excRes;
        _bufProp.executionReturnData = _excData;

        for (uint i; i < currentVoters.length; i++) {
            _bufProp.receipts[currentVoters[i]] =
                _authorizer.getReceipt(voteId, currentVoters[i]);
        }

        return _bufProp;
    }

    //--------------------------------------------------------------------------
    // TESTS: VOTE CREATION

    // Create vote correctly
    function testCreateVote() public {
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        for (uint i; i < initialVoters.length; i++) {
            uint _voteID = createVote(ALBA, _moduleAddress, _msg);

            ISingleVoteGovernor.Proposal storage _prop =
                getFullProposalData(_voteID);

            assertEq(_authorizer.proposalCount(), (_voteID + 1));
            assertEq(_prop.target, _moduleAddress);
            assertEq(_prop.action, _msg);
            assertEq(_prop.startTimestamp, block.timestamp);
            assertEq(_prop.endTimestamp, (block.timestamp + DEFAULT_DURATION));
            assertEq(_prop.requiredQuorum, DEFAULT_QUORUM);
            assertEq(_prop.forVotes, 0);
            assertEq(_prop.againstVotes, 0);
            assertEq(_prop.abstainVotes, 0);
            assertEq(_prop.executedAt, 0);
            assertEq(_prop.executionResult, false);
            assertEq(_prop.executionReturnData, "");
        }
    }

    // Fail to create a vote as non-voting address
    function testUnauthorizedVoteCreation(address[] memory users) public {
        _validateUserList(users);

        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        for (uint i; i < users.length; i++) {
            assertEq(_authorizer.isVoter(users[i]), false);
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__CallerNotVoter
                    .selector
            );
            vm.prank(users[i]);
            _authorizer.createProposal(_moduleAddress, _msg);
        }
    }

    // Add authorized address and have it create a vote
    function testCreateVoteWithRecentlyAuthorizedAddress(address[] memory users)
        public
    {
        _validateUserList(users);

        batchAddAuthorized(users);

        for (uint i; i < users.length; i++) {
            assertEq(_authorizer.isVoter(users[i]), true);

            //prank as that address, create a vote and vote on it
            (address _moduleAddress, bytes memory _msg) = getMockValidVote();
            uint _newVote = createVote(users[i], _moduleAddress, _msg);
            voteInFavor(users[i], _newVote);

            //assert that voting worked (also confirms that vote exists)
            assertEq(_authorizer.getReceipt(_newVote, users[i]).hasVoted, true);
        }
    }

    // Fail to create votes with wrong addresses and actions
    function testCreateWithInvalidVoteParamters(address wrongModule) public {
        vm.assume(wrongModule != address(module));
        vm.assume(wrongModule != address(_authorizer));
        vm.assume(wrongModule != address(_paymentProcessor));

        (address _moduleAddress, bytes memory _msg) = getMockValidVote();

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidTargetModule
                    .selector
            )
        );
        vm.prank(ALBA);
        _authorizer.createProposal(wrongModule, _msg);

        //Maybe discard this?
        /*
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernance__invalidEncodedAction
                    .selector,
                ""
            )
        );
        vm.prank(ALBA);
        _authorizer.createProposal(_moduleAddress, "");
        */
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

     
        ISingleVoteGovernor.Proposal storage _prop =
            getFullProposalData(_voteID);
        uint _votesBefore = _prop.forVotes;

        voteInFavor(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; i++) {
            vm.warp(startTime + i);
            voteInFavor(users[i], _voteID);
        }

        //vote in the last possible moment
        vm.warp(startTime + DEFAULT_DURATION);
        voteInFavor(BOB, _voteID);

        _prop = getFullProposalData(_voteID);

        assertEq(_prop.receipts[ALBA].hasVoted, true);
        assertEq(_prop.receipts[ALBA].support, 0);

        assertEq(_prop.receipts[BOB].hasVoted, true);
        assertEq(_prop.receipts[BOB].support, 0);

        for (uint i; i < users.length; i++) {
            assertEq(_prop.receipts[users[i]].hasVoted, true);
            assertEq(_prop.receipts[users[i]].support, 0);
        }

        assertEq(_prop.forVotes, (_votesBefore + 2 + users.length));
    }

    // Fail to vote in favor as unauthorized address
    function testVoteInFavorUnauthorized(address[] memory users) public {
        _validateUserList(users);

        //create vote as authorized user
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; i++) {
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

        ISingleVoteGovernor.Proposal storage _prop =
            getFullProposalData(_voteID);
        uint _votesBefore = _prop.againstVotes;

        voteAgainst(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; i++) {
            vm.warp(startTime + i);
            voteAgainst(users[i], _voteID);
        }

        //vote in the last possible moment
        vm.warp(startTime + DEFAULT_DURATION);
        voteAgainst(BOB, _voteID);

               _prop = getFullProposalData(_voteID);

        assertEq(_prop.receipts[ALBA].hasVoted, true);
        assertEq(_prop.receipts[ALBA].support, 1);

        assertEq(_prop.receipts[BOB].hasVoted, true);
        assertEq(_prop.receipts[BOB].support, 1);

        for (uint i; i < users.length; i++) {
            assertEq(_prop.receipts[users[i]].hasVoted, true);
            assertEq(_prop.receipts[users[i]].support, 1);
        }

        assertEq(_prop.againstVotes, (_votesBefore + 2 + users.length));
    }

    // Fail to vote against as unauthorized address
    function testVoteAgainstUnauthorized(address[] memory users) public {
        _validateUserList(users);
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; i++) {
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

        ISingleVoteGovernor.Proposal storage _prop =
            getFullProposalData(_voteID);
        uint _votesBefore = _prop.abstainVotes;

        voteAbstain(ALBA, _voteID);

        uint startTime = block.timestamp;

        for (uint i; i < users.length; i++) {
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

        for (uint i; i < users.length; i++) {
            _r = _authorizer.getReceipt(_voteID, users[i]);
            assertEq(_r.hasVoted, true);
            assertEq(_r.support, 2);
        }

        _prop = getFullProposalData(_voteID);

        assertEq(_prop.receipts[ALBA].hasVoted, true);
        assertEq(_prop.receipts[ALBA].support, 2);

        assertEq(_prop.receipts[BOB].hasVoted, true);
        assertEq(_prop.receipts[BOB].support, 2);

        for (uint i; i < users.length; i++) {
            assertEq(_prop.receipts[users[i]].hasVoted, true);
            assertEq(_prop.receipts[users[i]].support, 2);
        }

        assertEq(_prop.abstainVotes, (_votesBefore + 2 + users.length));
    }

    // Fail to vote abstain as unauthorized address
    function testAbstainUnauthorized(address[] memory users) public {
        _validateUserList(users);
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; i++) {
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

        for (uint i; i < nums.length; i++) {
            vm.assume(nums[i] < 100_000_000_000);
            vm.warp(block.timestamp + DEFAULT_DURATION + 1 + nums[i]);

            // For
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__ProposalVotingPhaseClosed
                    .selector
            );

            voteInFavor(ALBA, _voteID);

            // Against
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__ProposalVotingPhaseClosed
                    .selector
            );
            voteAgainst(ALBA, _voteID);

            //Abstain
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__ProposalVotingPhaseClosed
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

        for (uint i; i < wrongIDs.length; i++) {
            vm.assume(wrongIDs[i] > _voteID);
            uint wrongID = wrongIDs[i];

            // For
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidProposalId
                    .selector
            );

            voteInFavor(ALBA, wrongID);

            // Against
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidProposalId
                    .selector
            );

            voteAgainst(ALBA, wrongID);

            //Abstain
            vm.expectRevert(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__InvalidProposalId
                    .selector
            );
            voteAbstain(ALBA, wrongID);
        }
    }

    // Fail vote for after already voting (testing the three vote variants)
    function testDoubleVoting(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);
        //create vote
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _voteID = createVote(ALBA, _moduleAddress, _msg);

        for (uint i; i < users.length; i++) {
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
        _authorizer.executeProposal(_voteID);

        // 4) The proposal state has changed
        assertEq(_authorizer.voteDuration(), _newDuration);
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
                .Module__SingleVoteGovernor__QuorumNotReached
                .selector
        );
        _authorizer.executeProposal(_voteID);
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
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__ProposalInVotingPhase
                    .selector
            )
        );
        _authorizer.executeProposal(_voteID);
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
        _authorizer.executeProposal(_voteID);

        // 3) the proposal state has changed
        assertEq(_authorizer.voteDuration(), _newDuration);

        // 4) Now we test that we can't execute again:
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleVoteGovernor
                    .Module__SingleVoteGovernor__ProposalAlreadyExecuted
                    .selector
            )
        );
        _authorizer.executeProposal(_voteID);
    }

    // Fail to execute governance functions through governance-approved callbacks (testing all 4 limited functions)
    function testGovernanceLoopFails() public {
        // This isn't relevant anymore with the new contracts (since "onlyVoters" can vote)
        /* // 1) Create (but don't execute) a set of passed votes which could act on future governance decisions

        uint _futureVoteID = (_authorizer.proposalCount() + 3);

        bytes memory _encodedAction =
            abi.encodeWithSignature("castVote(uint256)", _futureVoteID);

        uint attackID_1 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );

        _encodedAction =
            abi.encodeWithSignature("voteAgainst(uint256)", _futureVoteID);

        uint attackID_2 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );

        _encodedAction =
            abi.encodeWithSignature("voteAbstain(uint256)", _futureVoteID);

        uint attackID_3 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );

        //create a vote susceptible to be attacked
        (address _moduleAddress, bytes memory _msg) = getMockValidVote();
        uint _targetVoteID = createVote(ALBA, _moduleAddress, _msg);
        assertEq(_futureVoteID, _targetVoteID);

        // All execution attempts should fail
        vm.expectRevert(
            abi.encodeWithSelector(IModule.Module__CallerNotAuthorized.selector)
        );
        _authorizer.executeProposal(attackID_1);

        vm.expectRevert(
            abi.encodeWithSelector(IModule.Module__CallerNotAuthorized.selector)
        );
        _authorizer.executeProposal(attackID_2);

        vm.expectRevert(
            abi.encodeWithSelector(IModule.Module__CallerNotAuthorized.selector)
        );
        _authorizer.executeProposal(attackID_3);

        //Also check that vote creation isn't allowed this way
        (_moduleAddress, _msg) = getMockValidVote();
        _encodedAction = abi.encodeWithSignature(
            "createProposal(address,bytes)", _moduleAddress, _msg
        );
        uint attackID_4 = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );
        vm.expectRevert(
            abi.encodeWithSelector(IModule.Module__CallerNotAuthorized.selector)
        );
        _authorizer.executeProposal(attackID_4);*/
    }

    function testAuthorizationTransfer(address[] memory users) public {
        vm.assume(users.length > 4);
        _validateUserList(users);

        uint middle = users.length / 2;

        address[] memory _from = new address[](middle);
        address[] memory _to = new address[](middle);

        for (uint i = 0; i < middle; i++) {
            _from[i] = users[i];
            _to[i] = users[users.length - (1 + i)];
        }

        batchAddAuthorized(_from);

        for (uint i; i < _from.length; i++) {
            // first, test a normal successful authorization transfer
            vm.prank(_from[i]);
            _authorizer.transferVotingRights(_to[i]);

            assertEq(_authorizer.isVoter(_from[i]), false);
            assertEq(_authorizer.isVoter(_to[i]), true);
        }
    }

    //--------------------------------------------------------------------------
    // TEST: QUORUM

    // Get correct quorum
    function testGetQuorum() public {
        assertEq(_authorizer.quorum(), DEFAULT_QUORUM);
    }

    // Set a new quorum
    function testProposalSetQuorum() public {
        uint _newQ = 1;

        vm.prank(address(_authorizer));
        _authorizer.setQuorum(_newQ);

        assertEq(_authorizer.quorum(), _newQ);
    }

    // Fail to set a quorum that's too damn high
    function testSetUnreachableQuorum(uint _newQ) public {
        vm.assume(_newQ > _authorizer.voterCount());

        vm.expectRevert(
            ISingleVoteGovernor
                .Module__SingleVoteGovernor__UnreachableQuorum
                .selector
        );
        vm.prank(address(_authorizer));
        _authorizer.setQuorum(_newQ);
    }

    // Fail to remove Authorized addresses until quorum is unreachble
    function testRemoveTooManyAuthorized() public {
        assertEq(address(_proposal), address(_authorizer.proposal()));

        vm.startPrank(address(_authorizer));
        _authorizer.removeVoter(COBIE);

        //this call would leave a 1 person list with 2 quorum
        vm.expectRevert(
            ISingleVoteGovernor
                .Module__SingleVoteGovernor__UnreachableQuorum
                .selector
        );
        _authorizer.removeVoter(BOB);

        vm.stopPrank();
    }

    // Fail to remove Authorized addresses until the voterlist is empty
    function testRemoveUntilVoterListEmpty() public {
        assertEq(address(_proposal), address(_authorizer.proposal()));

        vm.startPrank(address(_authorizer));
        _authorizer.setQuorum(0);

        _authorizer.removeVoter(COBIE);
        _authorizer.removeVoter(BOB);

        //this call would leave a 1 person list with 2 quorum
        vm.expectRevert(
            ISingleVoteGovernor.Module__SingleVoteGovernor__EmptyVoters.selector
        );
        _authorizer.removeVoter(ALBA);

        vm.stopPrank();
    }

    // Fail to change quorum when not the module itself
    function testUnauthorizedQuorumChange(address[] memory users) public {
        _validateUserList(users);
        batchAddAuthorized(users);

        uint _newQ = 1;
        for (uint i; i < users.length; i++) {
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(users[i]); //authorized, but not Proposal
            _authorizer.setQuorum(_newQ);
        }
    }

    //Change the quorum by going through governance
    function testGovernanceQuorumChange() public {
        uint _newQuorum = 1;

        // 1) Create and approve a vote
        bytes memory _encodedAction =
            abi.encodeWithSignature("setQuorum(uint256)", _newQuorum);
        uint _voteID = speedrunSuccessfulVote(
            address(_authorizer), _encodedAction, initialVoters
        );

        // 2) The vote gets executed by anybody
        _authorizer.executeProposal(_voteID);

        // 3) The proposal state has changed
        assertEq(_authorizer.quorum(), _newQuorum);
    }

    //--------------------------------------------------------------------------
    // TEST: VOTE DURATION

    // Get correct vote duration
    function testGetVoteDuration() public {
        assertEq(_authorizer.voteDuration(), DEFAULT_DURATION);
    }

    // Set new vote duration
    function testProposalSetVoteDuration() public {
        uint _newDur = 3 days;

        vm.prank(address(_authorizer));
        _authorizer.setVotingDuration(_newDur);

        assertEq(_authorizer.voteDuration(), _newDur);
    }

    //Set new duration bygoing through governance
    function testGovernanceVoteDurationChange() public {
        //already covered in:
        testVoteExecution();
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
        for (uint i; i < addrs.length; i++) {
            assumeValidUser(addrs[i]);

            // Assume contributor address unique.
            vm.assume(!userCache[addrs[i]]);

            // Add contributor address to cache.
            userCache[addrs[i]] = true;
        }
    }

    function assumeValidUser(address a) public {
        address[] memory invalids = createInvalidUsers();

        for (uint i; i < invalids.length; i++) {
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
