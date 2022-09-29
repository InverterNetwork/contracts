// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "../Test.t.sol";

contract ModuleManagerTest is ProposalBaseTest {
    // @todo mp: Make enchidna tests out of this.
    function testInvariants() public {
        // SENTINEL_MODULE is disabled.
        assertTrue(!proposal.isEnabledModule(SENTINEL_MODULE));

        // Not possible to enable SENTINEL_MODULE.
        // @todo mp: Implement after Proposal has public `disableModule`
        //           function.
        // proposal.disableModule(SENTINEL_MODULE);
        // assertTrue(!proposal.isEnabledModule(SENTINEL_MODULE));
    }

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

        // Check that each module is enabled.
        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            assertTrue(proposal.isEnabledModule(module));
        }

        // Check that SENTINEL_MODULE is disabled.
        assertTrue(!proposal.isEnabledModule(SENTINEL_MODULE));
    }

    function testInitilizationFailsForInvalidModuleAddress(
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

        // Set first module to address(0) or SENTINEL_MODULE.
        modules[0] = proposalId % 2 == 0 ? address(0) : SENTINEL_MODULE;

        vm.expectRevert(Errors.Proposal__ModuleManager__InvalidModuleAddress);
        proposal.initialize(proposalId, funders, modules, authorizer);
    }

    function testInitilizationFailsForDuplicateModules(
        uint proposalId,
        address[] memory funders,
        address[] memory modules
    )
        public
        assumeValidProposalId(proposalId)
        assumeValidFunders(funders)
        assumeValidModules(modules)
    {
        vm.assume(modules.length > 1);

        // Set first AND last module to authorizer instance.
        modules[0] = address(authorizer);
        modules[modules.length - 1] = address(authorizer);

        vm.expectRevert(
            Errors.Proposal__ModuleManager__ModuleAlreadyEnabled(
                address(authorizer)
            )
        );
        proposal.initialize(proposalId, funders, modules, authorizer);
    }

    function testExecuteTxFromModule() public {}
}
