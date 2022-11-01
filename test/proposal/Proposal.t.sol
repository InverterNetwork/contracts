// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

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

// Helpers
import {FuzzInputChecker} from "test/proposal/helper/FuzzInputChecker.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ProposalTest is Test, FuzzInputChecker {
    // SuT
    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;
    PaymentProcessorMock paymentProcessor;
    ERC20Mock token;

    function setUp() public {
        authorizer = new AuthorizerMock();
        paymentProcessor = new PaymentProcessorMock();
        token = new ERC20Mock("TestToken", "TST");

        proposal = new Proposal();
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        _assumeAddressNotInSet(modules, address(authorizer));
        _assumeAddressNotInSet(modules, address(paymentProcessor));
        _assumeAddressNotInSet(modules, address(token));

        // Initialize proposal.
        proposal.init(
            proposalId, token, funders, modules, authorizer, paymentProcessor
        );

        // Check that proposal's storage correctly initialized.
        assertEq(proposal.proposalId(), proposalId);
        assertEq(address(proposal.token()), address(token));
        assertEq(address(proposal.authorizer()), address(authorizer));
        assertEq(
            address(proposal.paymentProcessor()), address(paymentProcessor)
        );

        // Check that proposal's dependencies correctly initialized.
        // Ownable:
        assertEq(proposal.owner(), address(this));
        // Pausable:
        assertTrue(!proposal.paused());
    }

    function testReinitFails(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        _assumeAddressNotInSet(modules, address(authorizer));
        _assumeAddressNotInSet(modules, address(paymentProcessor));
        _assumeAddressNotInSet(modules, address(token));

        // Initialize proposal.
        proposal.init(
            proposalId, token, funders, modules, authorizer, paymentProcessor
        );

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        proposal.init(
            proposalId, token, funders, modules, authorizer, paymentProcessor
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTx() public {
        // @todo mp: Add Proposal::executeTx tests.
    }

    //--------------------------------------------------------------------------
    // Tests: Other

    function testVersion() public {
        assertEq(proposal.version(), "1");
    }
}
