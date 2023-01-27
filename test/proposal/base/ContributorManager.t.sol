// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

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

// Helper
import {TypeSanityHelper} from "test/proposal/helper/TypeSanityHelper.sol";

contract ContributorManagerTest is Test {
    // SuT
    ContributorManagerMock contributorManager;

    // Helper
    TypeSanityHelper types;

    // Constants
    uint constant MAX_CONTRIBUTORS = 20;

    string constant NAME = "name";
    string constant ROLE = "role";
    string constant UPDATED_ROLE = "updated role";
    string constant UPDATED_NAME = "updated name";

    // Constants copied from SuT.
    address private constant _SENTINEL = address(0x1);

    // Events copied from SuT.
    event ContributorAdded(address indexed who);
    event ContributorRemoved(address indexed who);
    event ContributorUpdated(address indexed who, string name, string role);

    function setUp() public {
        contributorManager = new ContributorManagerMock();
        contributorManager.init();

        types = new TypeSanityHelper(address(contributorManager));

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), true
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        // List of contributors should be empty.
        address[] memory contributors = contributorManager.listContributors();
        assertEq(contributors.length, 0);
    }

    function testReinitFails() public {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        contributorManager.init();
    }

    function testInitFailsForNonInitializerFunction() public {
        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        contributorManager.initNoInitializer();
    }

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    //----------------------------------
    // Tests: getPreviousContributor()

    function testGetPreviousContributor(address[] memory whos, uint randomWho)
        public
    {
        vm.assume(whos.length <= MAX_CONTRIBUTORS);
        types.assumeValidContributors(whos);

        //Make sure one of the existing contributors gets picked
        vm.assume(randomWho < whos.length);

        for (uint i; i < whos.length; i++) {
            contributorManager.addContributor(whos[i], NAME, ROLE);
        }

        address prevContr;

        if (randomWho == whos.length - 1) {
            prevContr = _SENTINEL;
        } else {
            prevContr = whos[randomWho + 1];
        }

        assertEq(
            contributorManager.getPreviousContributor(whos[randomWho]),
            prevContr
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Contributor Management

    //----------------------------------
    // Tests: addContributor()

    function testAddContributor(address[] memory whos) public {
        vm.assume(whos.length <= MAX_CONTRIBUTORS);
        types.assumeValidContributors(whos);

        for (uint i; i < whos.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit ContributorAdded(whos[i]);

            contributorManager.addContributor(whos[i], NAME, ROLE);

            assertTrue(contributorManager.isContributor(whos[i]));

            IContributorManager.Contributor memory c =
                contributorManager.getContributorInformation(whos[i]);
            assertEq(c.name, NAME);
            assertEq(c.role, ROLE);
        }

        // Note that list is traversed.
        address[] memory contributors = contributorManager.listContributors();

        assertEq(contributors.length, whos.length);
        for (uint i; i < whos.length; i++) {
            assertEq(contributors[i], whos[whos.length - i - 1]);
        }
    }

    function testAddContributorFailsIfCallerNotAuthorized(address who) public {
        types.assumeValidContributor(who);

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), false
        );

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__CallerNotAuthorized
                .selector
        );
        contributorManager.addContributor(who, NAME, ROLE);
    }

    function testAddContributorFailsIfAlreadyContributor(address who) public {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__IsContributor
                .selector
        );
        contributorManager.addContributor(who, NAME, ROLE);
    }

    function testAddContributorFailsForInvalidAddress() public {
        address[] memory invalids = types.createInvalidContributors();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorAddress
                    .selector
            );
            contributorManager.addContributor(invalids[i], NAME, ROLE);
        }
    }

    function testAddContributorFailsForInvalidName(address who) public {
        types.assumeValidContributor(who);

        string[] memory invalids = types.createInvalidContributorNames();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorName
                    .selector
            );
            contributorManager.addContributor(who, invalids[i], ROLE);
        }
    }

    function testAddContributorFailsForInvalidRole(address who) public {
        types.assumeValidContributor(who);

        string[] memory invalids = types.createInvalidContributorRoles();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorRole
                    .selector
            );
            contributorManager.addContributor(who, NAME, invalids[i]);
        }
    }

    //----------------------------------
    // Tests: removeContributor()

    function testRemoveContributor(address[] memory whos) public {
        vm.assume(whos.length != 0);
        vm.assume(whos.length <= MAX_CONTRIBUTORS);
        types.assumeValidContributors(whos);

        // The current contrib to remove.
        address contrib;
        // The contrib's prevContrib in the list.
        address prevContrib;

        // Add contributors.
        for (uint i; i < whos.length; i++) {
            contributorManager.addContributor(whos[i], NAME, ROLE);
        }

        // Remove contributors from the front until list is empty.
        for (uint i; i < whos.length; i++) {
            contrib = whos[whos.length - i - 1];

            vm.expectEmit(true, true, true, true);
            emit ContributorRemoved(contrib);

            contributorManager.removeContributor(_SENTINEL, contrib);

            assertTrue(!contributorManager.isContributor(contrib));

            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__IsNotContributor
                    .selector
            );
            contributorManager.getContributorInformation(contrib);
        }
        assertEq(contributorManager.listContributors().length, 0);

        // Add contributors again.
        for (uint i; i < whos.length; i++) {
            contributorManager.addContributor(whos[i], NAME, ROLE);
        }

        // Remove contributors from the back until list is empty.
        // Note that removing the last contributor requires the sentinel as
        // prevContrib.
        for (uint i; i < whos.length - 1; i++) {
            contrib = whos[i];
            prevContrib = whos[i + 1];

            vm.expectEmit(true, true, true, true);
            emit ContributorRemoved(contrib);

            contributorManager.removeContributor(prevContrib, contrib);

            assertTrue(!contributorManager.isContributor(contrib));

            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__IsNotContributor
                    .selector
            );
            contributorManager.getContributorInformation(contrib);
        }
        // Remove last contributor.
        contributorManager.removeContributor(_SENTINEL, whos[whos.length - 1]);

        assertEq(contributorManager.listContributors().length, 0);
    }

    function testRemoveContributorFailsIfCallerNotAuthorized(address who)
        public
    {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), false
        );

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__CallerNotAuthorized
                .selector
        );
        contributorManager.removeContributor(_SENTINEL, who);
    }

    function testRemoveContributorFailsIfNotContributor(address who) public {
        types.assumeValidContributor(who);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__IsNotContributor
                .selector
        );
        contributorManager.removeContributor(_SENTINEL, who);
    }

    function testRemoveContributorFailsIfNotConsecutiveContributorsGiven(
        address who
    ) public {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__ContributorsNotConsecutive
                .selector
        );
        contributorManager.removeContributor(address(0xCAFE), who);
    }

    //----------------------------------
    // Tests: updateContributorsRole()

    function testUpdateContributorFailsIfCallerNotAuthorized(address who)
        public
    {
        types.assumeValidContributor(who);

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), false
        );

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__CallerNotAuthorized
                .selector
        );
        contributorManager.updateContributor(who, NAME, UPDATED_ROLE);
    }

    function testUpdateContributorFailsIfNotContributor(address who) public {
        types.assumeValidContributor(who);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__IsNotContributor
                .selector
        );
        contributorManager.updateContributor(who, NAME, UPDATED_ROLE);
    }

    function testUpdateContributorsRole(address who) public {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        vm.expectEmit(true, true, true, true);
        emit ContributorUpdated(who, NAME, UPDATED_ROLE);

        contributorManager.updateContributor(who, NAME, UPDATED_ROLE);

        IContributorManager.Contributor memory c =
            contributorManager.getContributorInformation(who);
        assertEq(c.role, UPDATED_ROLE);
    }

    function testUpdateContributorsRoleFailsForInvalidRole(address who)
        public
    {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        string[] memory invalids = types.createInvalidContributorRoles();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorRole
                    .selector
            );
            contributorManager.updateContributor(who, NAME, invalids[i]);
        }
    }

    function testUpdateContributorsName(address who) public {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        vm.expectEmit(true, true, true, true);
        emit ContributorUpdated(who, UPDATED_NAME, ROLE);

        contributorManager.updateContributor(who, UPDATED_NAME, ROLE);

        IContributorManager.Contributor memory c =
            contributorManager.getContributorInformation(who);
        assertEq(c.name, UPDATED_NAME);
    }

    function testUpdateContributorsNameFailsForInvalidName(address who)
        public
    {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        string[] memory invalids = types.createInvalidContributorNames();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorName
                    .selector
            );
            contributorManager.updateContributor(who, invalids[i], ROLE);
        }
    }

    //----------------------------------
    // Tests: revokeContributor()

    function testRevokeContributor(address who) public {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        vm.prank(who);
        contributorManager.revokeContributor(_SENTINEL);

        assertTrue(!contributorManager.isContributor(who));
    }

    function testRemoveContributorFailsIfCallerNotContributor(address who)
        public
    {
        types.assumeValidContributor(who);

        vm.prank(who);
        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__IsNotContributor
                .selector
        );
        contributorManager.revokeContributor(_SENTINEL);
    }

    function testRevokeContributorFailsIfNotConsecutiveContributorsGiven(
        address who
    ) public {
        types.assumeValidContributor(who);

        contributorManager.addContributor(who, NAME, ROLE);

        vm.prank(who);
        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__ContributorsNotConsecutive
                .selector
        );
        contributorManager.revokeContributor(address(0xCAFE));
    }
}
