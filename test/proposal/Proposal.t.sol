// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./Test.t.sol";

contract ProposalTest is ProposalBaseTest {
    function testInitialization(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    )
        public
        assumeValidProposalId(proposalId)
        assumeValidFunders(funders)
        assumeValidModules(modules)
    {
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
    )
        public
        assumeValidProposalId(proposalId)
        assumeValidFunders(funders)
        assumeValidModules(modules)
    {
        // Set last module to authorizer instance.
        modules[modules.length - 1] = address(authorizer);

        // Initialize proposal.
        proposal.initialize(proposalId, funders, modules, authorizer);

        vm.expectRevert(Errors.OZ__Initializable__AlreadyInitialized);
        proposal.initialize(proposalId, funders, modules, authorizer);
    }

    function testInitializationFailsForInvalidAuthorizer(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    )
        public
        assumeValidProposalId(proposalId)
        assumeValidFunders(funders)
        assumeValidModules(modules)
    {
        // Note that the authorizer is not added to the modules list.
        vm.expectRevert(Errors.Proposal__InvalidAuthorizer);
        proposal.initialize(proposalId, funders, modules, authorizer);
    }

    function testExecuteTx() public {
        // @todo mp: Add Proposal::executeTx tests.
    }

    function testVersion() public {
        assertEq(proposal.version(), "1");
    }
}
