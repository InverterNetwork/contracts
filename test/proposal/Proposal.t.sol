// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

// Helpers
import {FuzzInputChecker} from "test/proposal/helper/FuzzInputChecker.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

/**
 * Errors library for Proposal's custom errors.
 * Enables checking for errors with vm.expectRevert(Errors.<Error>).
 */
library Errors {
    bytes internal constant Proposal__CallerNotAuthorized =
        abi.encodeWithSignature("Proposal__CallerNotAuthorized()");

    bytes internal constant Proposal__InvalidAuthorizer =
        abi.encodeWithSignature("Proposal__InvalidAuthorizer()");

    bytes internal constant Proposal__ExecuteTxFailed =
        abi.encodeWithSignature("Proposal__ExecuteTxFailed()");
}

contract ProposalTest is Test, FuzzInputChecker {
    // SuT
    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;

    function setUp() public {
        authorizer = new AuthorizerMock();

        proposal = new Proposal();
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInitialization(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Set last module to authorizer instance.
        modules[modules.length - 1] = address(authorizer);

        // Initialize proposal.
        proposal.initialize(proposalId, funders, modules, authorizer);

        // Check that proposal's storage correctly initialized.
        assertEq(address(proposal.authorizer()), address(authorizer));
    }

    function testReinitializationFails(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Set last module to authorizer instance.
        modules[modules.length - 1] = address(authorizer);

        // Initialize proposal.
        proposal.initialize(proposalId, funders, modules, authorizer);

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        proposal.initialize(proposalId, funders, modules, authorizer);
    }

    function testInitializationFailsForInvalidAuthorizer(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Note that the authorizer is not added to the modules list.
        vm.expectRevert(Errors.Proposal__InvalidAuthorizer);
        proposal.initialize(proposalId, funders, modules, authorizer);
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
