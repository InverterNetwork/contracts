// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Internal Interfaces
import {
    IProposal,
    IAuthorizer,
    IPaymentProcessor
} from "src/proposal/IProposal.sol";

// Mocks
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Helper
import {TypeSanityHelper} from "test/proposal/helper/TypeSanityHelper.sol";

contract ProposalTest is Test {
    // SuT
    Proposal proposal;

    // Helper
    TypeSanityHelper types;

    // Mocks
    FundingManagerMock fundingManager;
    AuthorizerMock authorizer;
    PaymentProcessorMock paymentProcessor;
    ERC20Mock token;

    function setUp() public {
        fundingManager = new FundingManagerMock();
        authorizer = new AuthorizerMock();
        paymentProcessor = new PaymentProcessorMock();
        token = new ERC20Mock("TestToken", "TST");

        address impl = address(new Proposal());
        proposal = Proposal(Clones.clone(impl));

        types = new TypeSanityHelper(address(proposal));
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(uint proposalId, address[] memory modules) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        // Check that proposal's storage correctly initialized.
        assertEq(proposal.proposalId(), proposalId);
        assertEq(address(proposal.manager()), address(this));
        assertEq(address(proposal.token()), address(token));
        assertEq(address(proposal.authorizer()), address(authorizer));
        assertEq(
            address(proposal.paymentProcessor()), address(paymentProcessor)
        );

        // Check that proposal's dependencies correctly initialized.
        // Ownable:
        assertEq(proposal.manager(), address(this));
    }

    function testReinitFails(uint proposalId, address[] memory modules)
        public
    {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTx(uint proposalId, address[] memory modules) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        bytes memory returnData =
            proposal.executeTx(address(this), abi.encodeWithSignature("ok()"));
        assertTrue(abi.decode(returnData, (bool)));
    }

    function testExecuteTxFailsIfCallFails(
        uint proposalId,
        address[] memory modules
    ) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(this),
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), true);

        vm.expectRevert(IProposal.Proposal__ExecuteTxFailed.selector);
        proposal.executeTx(address(this), abi.encodeWithSignature("fails()"));
    }

    function testExecuteTxFailsIfCallerNotAuthorized(
        uint proposalId,
        address[] memory modules
    ) public {
        types.assumeValidProposalId(proposalId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize proposal.
        proposal.init(
            proposalId,
            address(0xCAFE), // Note to not be the owner
            token,
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );

        authorizer.setIsAuthorized(address(this), false);

        vm.expectRevert(IProposal.Proposal__CallerNotAuthorized.selector);
        proposal.executeTx(address(this), abi.encodeWithSignature("ok()"));
    }

    function ok() public pure returns (bool) {
        return true;
    }

    function fails() public pure {
        revert("failed");
    }

    //--------------------------------------------------------------------------
    // Tests: Other

    function testVersion() public {
        assertEq(proposal.version(), "1");
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function assumeMockAreNotInSet(address[] memory modules) private view {
        types.assumeElemNotInSet(modules, address(fundingManager));
        types.assumeElemNotInSet(modules, address(authorizer));
        types.assumeElemNotInSet(modules, address(paymentProcessor));
        types.assumeElemNotInSet(modules, address(token));
    }
}
