// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IPayer} from "src/interfaces/IPayer.sol";

// Helpers
import {FuzzInputChecker} from "test/proposal/helper/FuzzInputChecker.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {PayerMock} from "test/utils/mocks/PayerMock.sol";

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

    bytes internal constant Proposal__InvalidPayer =
        abi.encodeWithSignature("Proposal__InvalidPayer()");

    bytes internal constant Proposal__ExecuteTxFailed =
        abi.encodeWithSignature("Proposal__ExecuteTxFailed()");
}

contract ProposalTest is Test, FuzzInputChecker {
    // SuT
    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;
    PayerMock payer;

    function setUp() public {
        authorizer = new AuthorizerMock();
        payer = new PayerMock();

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

        // Set last two modules to authorizer and payer instances.
        modules[modules.length - 2] = address(authorizer);
        modules[modules.length - 1] = address(payer);

        // Initialize proposal.
        proposal.init(proposalId, funders, modules, authorizer, payer);

        // Check that proposal's storage correctly initialized.
        assertEq(address(proposal.authorizer()), address(authorizer));
    }

    function testReinitFails(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Set last two modules to authorizer and payer instances.
        modules[modules.length - 2] = address(authorizer);
        modules[modules.length - 1] = address(payer);

        // Initialize proposal.
        proposal.init(proposalId, funders, modules, authorizer, payer);

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        proposal.init(proposalId, funders, modules, authorizer, payer);
    }

    function testInitFailsForInvalidAuthorizer(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Set last module to payer instance.
        modules[modules.length - 1] = address(payer);

        // Note that the authorizer is not added to the modules list.
        vm.expectRevert(Errors.Proposal__InvalidAuthorizer);
        proposal.init(proposalId, funders, modules, authorizer, payer);
    }

    function testInitFailsForInvalidPayer(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    ) public {
        _assumeValidProposalId(proposalId);
        _assumeValidFunders(funders);
        _assumeValidModules(modules);

        // Set last module to authorizer instance.
        modules[modules.length - 1] = address(authorizer);

        // Note that the payer is not added to the modules list.
        vm.expectRevert(Errors.Proposal__InvalidPayer);
        proposal.init(proposalId, funders, modules, authorizer, payer);
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
