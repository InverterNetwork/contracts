// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
import {Payment} from "src/modules/Payment.sol";

// Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract PaymentTest is Test {
    Proposal proposal;
    ContributorManager contributorModule;

    // Mocks
    AuthorizerMock authorizer;

    function setUp() public {
        authorizer = new AuthorizerMock();
        authorizer.setIsAuthorized(address(this), true);

        proposal = new Proposal();
        contributorModule = new ContributorManager();

        // Init proposal with payment module.
        address[] memory funders = new address[](1);
        funders[0] = address(this);
        address[] memory modules = new address[](2);
        modules[0] = address(contributorModule);
        modules[1] = address(authorizer);
        proposal.initialize(1, funders, modules, IAuthorizer(authorizer));

        // Init module.
        bytes memory data = bytes("");
        contributorModule.initialize(IProposal(proposal), data);
    }

    function testAddContributor() public {
        address bob = new address(0xb0b);
        bytes32 role = keccak256("DEV");
        uint salary = 25000;

        
        contributorModule.addContributor(bob, role, salary);

        assertEq(contributorModule.isActiveContributor(bob), true);
    }


    function testRemoveLastContributor() public {
        address bob = new address(0xb0b);
        bytes32 role = keccak256("DEV");
        uint salary = 25000;

        
        contributorModule.addContributor(bob, role, salary);

        contributorModule.removeContributor(bob, address(0x1));

        assertEq(contributorModule.isActiveContributor(bob), false);
        assertEq(contributorModulel.istActiveContributors().length, 0)
    }
}
