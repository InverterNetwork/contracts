// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
import {ContributorManager} from "src/modules/governance/ContributorManager.sol";

// Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ContributorManagerTest is Test {
    ContributorManager contributorModule;

    // Mocks
    AuthorizerMock authorizer;
    ProposalMock proposal;

    function setUp() public {
        authorizer = new AuthorizerMock();
        authorizer.setAllAuthorized(true);

        proposal = new ProposalMock(authorizer);

        contributorModule = new ContributorManager();

        // Init proposal with contributor module.
        address[] memory modules = new address[](1);
        modules[0] = address(contributorModule);

        proposal.init(modules);

        bytes memory data = bytes("");
        contributorModule.initialize(IProposal(proposal), data);

        assertEq(address(contributorModule.proposal()), address(proposal));
        assertEq(
            address(contributorModule.proposal().authorizer()),
            address(authorizer)
        );
    }

    function testAddContributor() public {
        address bob = address(0xb0b);
        bytes32 role = keccak256("DEV");
        uint salary = 25_000;

        contributorModule.addContributor(bob, role, salary);

        assertEq(contributorModule.isActiveContributor(bob), true);
    }

    function testRemoveLastContributor() public {
        address bob = address(0xb0b);
        bytes32 role = keccak256("DEV");
        uint salary = 25_000;

        contributorModule.addContributor(bob, role, salary);

        contributorModule.removeContributor(bob, address(0x1));

        assertEq(contributorModule.isActiveContributor(bob), false);
        assertEq(contributorModule.listActiveContributors().length, 0);
    }
}
