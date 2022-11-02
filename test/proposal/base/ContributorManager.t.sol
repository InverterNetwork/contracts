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

    // Constants
    uint constant MAX_CONTRIBUTORS = 20;

    string constant NAME = "name";
    string constant ROLE = "role";
    string constant UPDATED_ROLE = "updated role";
    uint constant SALARY = 1e18;
    uint constant UPDATED_SALARY = 2e18;

    // Constants copied from SuT.
    address private constant _SENTINEL = address(0x1);

    // Events copied from SuT.
    event ContributorAdded(address indexed who);
    event ContributorRemoved(address indexed who);
    event ContributorsRoleUpdated(
        address indexed who, string newRole, string oldRole
    );
    event ContributorsSalaryUpdated(
        address indexed who, uint newSalary, uint oldSalary
    );

    function setUp() public {
        contributorManager = new ContributorManagerMock();
        contributorManager.init();

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), true
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        contributorManager = new ContributorManagerMock();
        contributorManager.init();

        // List of contributors should be empty.
        address[] memory contributors = contributorManager.listContributors();
        assertEq(contributors.length, 0);
    }

    function testReinitFails() public {
        contributorManager = new ContributorManagerMock();
        contributorManager.init();

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        contributorManager.reinit();
    }

    //--------------------------------------------------------------------------
    // Tests: Contributor Management

    //----------------------------------
    // Tests: addContributor()

    function testAddContributor(address[] memory whos) public {
        vm.assume(whos.length <= MAX_CONTRIBUTORS);
        _assumeValidAddresses(whos);

        for (uint i; i < whos.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit ContributorAdded(whos[i]);

            contributorManager.addContributor(whos[i], NAME, ROLE, SALARY);

            assertTrue(contributorManager.isContributor(whos[i]));

            IContributorManager.Contributor memory c =
                contributorManager.getContributorInformation(whos[i]);
            assertEq(c.name, NAME);
            assertEq(c.role, ROLE);
            assertEq(c.salary, SALARY);
        }

        // Note that list is traversed.
        address[] memory contributors = contributorManager.listContributors();

        assertEq(contributors.length, whos.length);
        for (uint i; i < whos.length; i++) {
            assertEq(contributors[i], whos[whos.length - i - 1]);
        }
    }

    function testAddContributorFailsIfCallerNotAuthorized(address who) public {
        _assumeValidAddress(who);

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), false
        );

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__CallerNotAuthorized
                .selector
        );
        contributorManager.addContributor(who, NAME, ROLE, SALARY);
    }

    function testAddContributorFailsIfAlreadyContributor(address who) public {
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__IsContributor
                .selector
        );
        contributorManager.addContributor(who, NAME, ROLE, SALARY);
    }

    function testAddContributorFailsForInvalidAddress() public {
        address[] memory invalids = _createInvalidAddresses();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorAddress
                    .selector
            );
            contributorManager.addContributor(invalids[i], NAME, ROLE, SALARY);
        }
    }

    function testAddContributorFailsForInvalidName(address who) public {
        _assumeValidAddress(who);

        string[] memory invalids = _createInvalidNames();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorName
                    .selector
            );
            contributorManager.addContributor(who, invalids[i], ROLE, SALARY);
        }
    }

    function testAddContributorFailsForInvalidRole(address who) public {
        _assumeValidAddress(who);

        string[] memory invalids = _createInvalidRoles();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorRole
                    .selector
            );
            contributorManager.addContributor(who, NAME, invalids[i], SALARY);
        }
    }

    function testAddContributorFailsForInvalidSalary(address who) public {
        _assumeValidAddress(who);

        uint[] memory invalids = _createInvalidSalaries();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorSalary
                    .selector
            );
            contributorManager.addContributor(who, NAME, ROLE, invalids[i]);
        }
    }

    //----------------------------------
    // Tests: removeContributor()

    function testRemoveContributor(address[] memory whos) public {
        vm.assume(whos.length != 0);
        vm.assume(whos.length <= MAX_CONTRIBUTORS);
        _assumeValidAddresses(whos);

        // The current contrib to remove.
        address contrib;
        // The contrib's prevContrib in the list.
        address prevContrib;

        // Add contributors.
        for (uint i; i < whos.length; i++) {
            contributorManager.addContributor(whos[i], NAME, ROLE, SALARY);
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
            contributorManager.addContributor(whos[i], NAME, ROLE, SALARY);
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
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

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
        _assumeValidAddress(who);

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
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__ContributorsNotConsecutive
                .selector
        );
        contributorManager.removeContributor(address(0xCAFE), who);
    }

    //----------------------------------
    // Tests: updateContributorsRole()

    function testUpdateContributorsRole(address who) public {
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        vm.expectEmit(true, true, true, true);
        emit ContributorsRoleUpdated(who, UPDATED_ROLE, ROLE);

        contributorManager.updateContributorsRole(who, UPDATED_ROLE);

        IContributorManager.Contributor memory c =
            contributorManager.getContributorInformation(who);
        assertEq(c.role, UPDATED_ROLE);
    }

    function testUpdateContributorsRoleFailsIfCallerNotAuthorized(address who)
        public
    {
        _assumeValidAddress(who);

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), false
        );

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__CallerNotAuthorized
                .selector
        );
        contributorManager.updateContributorsRole(who, UPDATED_ROLE);
    }

    function testUpdateContributorsRoleFailsIfNotContributor(address who)
        public
    {
        _assumeValidAddress(who);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__IsNotContributor
                .selector
        );
        contributorManager.updateContributorsRole(who, UPDATED_ROLE);
    }

    function testUpdateContributorsRoleFailsForInvalidRole(address who)
        public
    {
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        string[] memory invalids = _createInvalidRoles();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorRole
                    .selector
            );
            contributorManager.updateContributorsRole(who, invalids[i]);
        }
    }

    //----------------------------------
    // Tests: updateContributorsSalary()

    function testUpdateContributorsSalary(address who) public {
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        vm.expectEmit(true, true, true, true);
        emit ContributorsSalaryUpdated(who, UPDATED_SALARY, SALARY);

        contributorManager.updateContributorsSalary(who, UPDATED_SALARY);

        IContributorManager.Contributor memory c =
            contributorManager.getContributorInformation(who);
        assertEq(c.salary, UPDATED_SALARY);
    }

    function testUpdateContributorsSalaryFailsIfCallerNotAuthorized(address who)
        public
    {
        _assumeValidAddress(who);

        contributorManager.__ContributorManager_setIsAuthorized(
            address(this), false
        );

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__CallerNotAuthorized
                .selector
        );
        contributorManager.updateContributorsSalary(who, UPDATED_SALARY);
    }

    function testUpdateContributorsSalaryFailsIfNotContributor(address who)
        public
    {
        _assumeValidAddress(who);

        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__IsNotContributor
                .selector
        );
        contributorManager.updateContributorsSalary(who, UPDATED_SALARY);
    }

    function testUpdateContributorsSalaryFailsForInvalidSalary(address who)
        public
    {
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        uint[] memory invalids = _createInvalidSalaries();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IContributorManager
                    .Proposal__ContributorManager__InvalidContributorSalary
                    .selector
            );
            contributorManager.updateContributorsSalary(who, invalids[i]);
        }
    }

    //----------------------------------
    // Tests: revokeContributor()

    function testRevokeContributor(address who) public {
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        vm.prank(who);
        contributorManager.revokeContributor(_SENTINEL);

        assertTrue(!contributorManager.isContributor(who));
    }

    function testRemoveContributorFailsIfCallerNotContributor(address who)
        public
    {
        _assumeValidAddress(who);

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
        _assumeValidAddress(who);

        contributorManager.addContributor(who, NAME, ROLE, SALARY);

        vm.prank(who);
        vm.expectRevert(
            IContributorManager
                .Proposal__ContributorManager__ContributorsNotConsecutive
                .selector
        );
        contributorManager.revokeContributor(address(0xCAFE));
    }

    //--------------------------------------------------------------------------
    // Fuzzer Helper Functions

    mapping(address => bool) addressCache;

    function _assumeValidAddresses(address[] memory addrs) internal {
        for (uint i; i < addrs.length; i++) {
            _assumeValidAddress(addrs[i]);

            // Assume address unique.
            vm.assume(!addressCache[addrs[i]]);

            // Add address to cache.
            addressCache[addrs[i]] = true;
        }
    }

    function _assumeValidAddress(address a) internal {
        address[] memory invalids = _createInvalidAddresses();

        for (uint i; i < invalids.length; i++) {
            vm.assume(a != invalids[i]);
        }
    }

    //--------------------------------------------------------------------------
    // Data Creation Helper Functions

    function _createInvalidAddresses()
        internal
        view
        returns (address[] memory)
    {
        address[] memory invalids = new address[](3);

        invalids[0] = address(0);
        invalids[1] = _SENTINEL;
        invalids[2] = address(contributorManager);

        return invalids;
    }

    function _createInvalidNames() internal pure returns (string[] memory) {
        string[] memory invalids = new string[](1);

        invalids[0] = "";

        return invalids;
    }

    function _createInvalidRoles() internal pure returns (string[] memory) {
        string[] memory invalids = new string[](1);

        invalids[0] = "";

        return invalids;
    }

    function _createInvalidSalaries() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint[](1);

        invalids[0] = 0;

        return invalids;
    }
}
