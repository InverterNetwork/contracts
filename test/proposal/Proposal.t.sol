// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IPaymentProcessor} from "src/interfaces/IPaymentProcessor.sol";

// Helpers
import {FuzzInputChecker} from "test/proposal/helper/FuzzInputChecker.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {PaymentProcessorMock} from "test/utils/mocks/PaymentProcessorMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ProposalTest is Test, FuzzInputChecker {
    // SuT
    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;
    PaymentProcessorMock paymentProcessor;

    function setUp() public {
        authorizer = new AuthorizerMock();
        paymentProcessor = new PaymentProcessorMock();

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

        // Set last two module to authorizer and paymentProcessor.
        modules[modules.length - 1] = address(authorizer);
        modules[modules.length - 2] = address(paymentProcessor);

        // Initialize proposal.
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor
        );

        // Check that proposal's storage correctly initialized.
        assertEq(address(proposal.authorizer()), address(authorizer));
        assertEq(
            address(proposal.paymentProcessor()), address(paymentProcessor)
        );
    }

    function testReinitFails(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Set last two module to authorizer and paymentProcessor.
        modules[modules.length - 1] = address(authorizer);
        modules[modules.length - 2] = address(paymentProcessor);

        // Initialize proposal.
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor
        );

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor
        );
    }

    function testInitFailsForInvalidAuthorizer(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Note that the authorizer is not added to the modules list.
        modules[modules.length - 1] = address(paymentProcessor);

        vm.expectRevert(IProposal.Proposal__InvalidAuthorizer.selector);
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor
        );
    }

    function testInitFailsForInvalidPaymentProcessor(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Note that the paymentProcessor is not added to the modules list.
        modules[modules.length - 1] = address(authorizer);

        vm.expectRevert(IProposal.Proposal__InvalidPaymentProcessor.selector);
        proposal.init(
            proposalId, funders, modules, authorizer, paymentProcessor
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
