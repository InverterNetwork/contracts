// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

contract ProposalTest is Test {
    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;

    function setUp() public {
        authorizer = new AuthorizerMock();

        proposal = new Proposal();
    }

    function testVersion() public {
        assertEq(proposal.version(), "1");
    }

    function ttestInitialize(uint proposalId, uint numFunders, uint numModules)
        public
    {
        // Stay within reasonable array sizes.
        vm.assume(numFunders < 500 && numModules < 500);

        // Need at least one module being the IAuthorizer.
        vm.assume(numModules != 0);

        // Populate funders array with non-zero addresses.
        address[] memory funders = new address[](numFunders);
        for (uint i; i < numFunders; i++) {
            funders[i] = address(uint160(i + 1));
        }

        // Populate modules array with non-zero addresses.
        address[] memory modules = new address[](numModules);
        for (uint i; i < numModules - 1; i++) {
            modules[i] = address(uint160(i + 1));
        }
        modules[numModules - 1] = address(authorizer);

        // Initialize proposal.
        proposal.initialize(
            proposalId, funders, modules, IAuthorizer(authorizer)
        );

        // Check that proposal's storage correctly initialized.
        assertEq(address(proposal.authorizer()), address(authorizer));

        // Check that modules correctly activated.
        for (uint i; i < numModules; i++) {
            assertTrue(proposal.isEnabledModule(modules[i]));
        }
    }
}
