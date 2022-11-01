// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// Internal Dependencies
import {Proposal, IProposal} from "src/proposal/Proposal.sol";
import {IAuthorizer} from "src/modules/IAuthorizer.sol";
import {IModule} from "src/modules/base/IModule.sol";

// SuT
import {
    ContributorManagerMock,
    IContributorManager
} from "test/utils/mocks/proposal/base/ContributorManagerMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ContributorManagerTest is Test {
    // SuT
    ContributorManagerMock contributorManager;

    function setUp() public {
        contributorManager = new ContributorManagerMock();
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        contributorManager.init();
    }

    function testReinitFails() public {
        contributorManager.init();

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        contributorManager.reinit();
    }

    //--------------------------------------------------------------------------
    // Tests: Contributor Management

    /*
        // Create a set of contributors.
        contributors.push(MockContributor(address(0xa1ba), "LEAD", 50_000));
        contributors.push(
            MockContributor(address(0xb0b), "DEV-BACKEND", 35_000)
        );
        contributors.push(
            MockContributor(address(0xc0b1e), "COMMUNITY", 69_420)
        );
        contributors.push(
            MockContributor(address(0xd0bb1e), "FREE-CONTRACTOR", 10)
        );
        contributors.push(
            MockContributor(address(0xed), "DEV-FRONTEND", 35_000)
        );

        // Init proposal with contributor module.
        address[] memory modules = new address[](1);
        modules[0] = address(contributorModule);

        proposal.init(modules);

        IModule.Metadata memory data =
            IModule.Metadata(1, "https://www.github.com");
        contributorModule.initialize(IProposal(proposal), data);

        assertEq(address(contributorModule.proposal()), address(proposal));
        assertEq(
            address(contributorModule.proposal().authorizer()),
            address(authorizer)
        );
    }

    function fillContributorList() public {
        vm.startPrank(address(proposal));
        for (uint i = 0; i < contributors.length; i++) {
            contributorModule.__Contributor_addContributor(
                contributors[i].addr,
                contributors[i].role,
                contributors[i].salary
            );
        }
        vm.stopPrank();
    }

    function testAddContributor() public {
        //-------------------------------------------------------
        // Test: Add to empty list
        fillContributorList();

        //-------------------------------------------------------
        // Test: Add to initialized list
        MockContributor memory felicia =
            MockContributor(address(0xfe11c1a), "AUDITOR", 100_000);

        vm.prank(address(proposal));
        contributorModule.__Contributor_addContributor(
            felicia.addr, felicia.role, felicia.salary
        );

        assertEq(contributorModule.isActiveContributor(felicia.addr), true);

        assertEq(
            contributorModule.listActiveContributors().length,
            (contributors.length + 1)
        );

        //-------------------------------------------------------
        // Test fail: add existing contributor
        vm.expectRevert(
            ContributorManager
                .Module__ContributorManager__contributorAlreadyActive
                .selector
        );
        vm.prank(address(proposal));
        contributorModule.__Contributor_addContributor(
            felicia.addr, felicia.role, felicia.salary
        );
    }

    function testRemoveSingleContributor() public {
        fillContributorList();

        //-------------------------------------------------------
        // Test: Remove first contributor

        vm.prank(address(proposal));
        contributorModule.__Contributor_removeContributor(
            contributors[0].addr, contributors[1].addr
        );

        assertEq(
            contributorModule.isActiveContributor(contributors[0].addr), false
        );
        assertEq(contributorModule.listActiveContributors().length, 4);

        // test: remove last contributor
        MockContributor memory ed = contributors[contributors.length - 1];

        vm.prank(address(proposal));
        contributorModule.__Contributor_removeContributor(ed.addr, address(0x1));

        assertEq(contributorModule.isActiveContributor(ed.addr), false);
        assertEq(contributorModule.listActiveContributors().length, 3);

        //-------------------------------------------------------
        // Test: Remove contributor in the middle
        vm.prank(address(proposal));
        contributorModule.__Contributor_removeContributor(
            contributors[2].addr, contributors[3].addr
        );

        assertEq(
            contributorModule.isActiveContributor(contributors[2].addr), false
        );
        assertEq(contributorModule.listActiveContributors().length, 2);

        //-------------------------------------------------------
        // Test fail: remove non consecutive contributors
        vm.expectRevert(
            ContributorManager
                .Module__ContributorManager__ContributorsNotConsecutive
                .selector
        );
        vm.prank(address(proposal));
        contributorModule.__Contributor_removeContributor(
            contributors[1].addr, contributors[4].addr
        );

        //-------------------------------------------------------
        // Test fail: Remove non existing contributor
        ///          @note: The function removeContributor() is idempotent, so
        ///          removing  a non existing contributor would just do nothing.
        ///          But since we're calling "__Contributor_removeContributor()"
        ///          directly (the call that takes place AFTER checking for
        ///          that), the revert will be ContributorsNotConsecutive
        ///          (which would be the problem if such a call somehow passed
        ///          the previous checks).

        vm.expectRevert(
            ContributorManager
                .Module__ContributorManager__ContributorsNotConsecutive
                .selector
        );
        vm.prank(address(proposal));
        contributorModule.__Contributor_removeContributor(ed.addr, address(0x1));
    }

    function testRemoveAllContributors() public {
        fillContributorList();

        //-------------------------------------------------------
        // Test: remove from the front until list is empty

        address[] memory contribList =
            contributorModule.listActiveContributors();

        for (uint i = 0; i < contribList.length; i++) {
            vm.prank(address(proposal));
            contributorModule.__Contributor_removeContributor(
                contribList[i], address(0x1)
            );
        }
        assertEq(contributorModule.listActiveContributors().length, 0);

        //-------------------------------------------------------
        // Test: Remove from the back until list is empty
        fillContributorList();

        contribList = contributorModule.listActiveContributors();

        for (uint i = (contribList.length - 1); i > 0; i--) {
            vm.prank(address(proposal));
            contributorModule.__Contributor_removeContributor(
                contribList[i], contribList[i - 1]
            );
        }
        /// @note removing the last contributor requires sending the sentinel:
        vm.prank(address(proposal));
        contributorModule.__Contributor_removeContributor(
            contribList[0], address(0x1)
        );
        assertEq(contributorModule.listActiveContributors().length, 0);
    }

    function testModifyContributor() public {
        fillContributorList();

        //-------------------------------------------------------
        // Test: Remove contributor and add them again with new info

        vm.prank(address(proposal));
        contributorModule.__Contributor_removeContributor(
            contributors[0].addr, contributors[1].addr
        );

        assertEq(
            contributorModule.isActiveContributor(contributors[0].addr), false
        );
        assertEq(
            contributorModule.listActiveContributors().length,
            (contributors.length - 1)
        );

        vm.prank(address(proposal));
        contributorModule.__Contributor_addContributor(
            contributors[0].addr, "NEWROLE", 200_000
        );

        (bytes32 newRole, uint newSal) =
            contributorModule.getContributorInformation(contributors[0].addr);

        assertEq(
            contributorModule.isActiveContributor(contributors[0].addr), true
        );
        assertEq(
            contributorModule.listActiveContributors().length,
            contributors.length
        );
        assertEq("NEWROLE", newRole);
        assertEq(200_000, newSal);

        //-------------------------------------------------------
        // Test: Modify contributor
        vm.prank(address(proposal));
        contributorModule.__Contributor_modifyContributor(
            contributors[0].addr, contributors[0].role, contributors[0].salary
        );

        (newRole, newSal) =
            contributorModule.getContributorInformation(contributors[0].addr);

        assertEq(
            contributorModule.isActiveContributor(contributors[0].addr), true
        );
        assertEq(contributors[0].role, newRole);
        assertEq(contributors[0].salary, newSal);
    }
    */
}
