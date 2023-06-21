// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";

import {
    RoleAuthorizer,
    IRoleAuthorizer
} from "src/modules/authorizer/RoleAuthorizer.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
// Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";
// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

contract RoleAuthorizerTest is Test {
    // Mocks
    RoleAuthorizer _authorizer;
    Proposal internal _proposal = new Proposal();
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    FundingManagerMock _fundingManager = new FundingManagerMock();
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();
    address ALBA = address(0xa1ba); //default authorized person
    address BOB = address(0xb0b); // example person to add
    // Proposal Constants
    uint internal constant _PROPOSAL_ID = 1;
    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public {
        address authImpl = address(new RoleAuthorizer());
        _authorizer = RoleAuthorizer(Clones.clone(authImpl));
        address propImpl = address(new Proposal());
        _proposal = Proposal(Clones.clone(propImpl));
        ModuleMock module = new  ModuleMock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        _proposal.init(
            _PROPOSAL_ID,
            address(this),
            _token,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor
        );

        address[] memory initialAuth = new address[](1);
        initialAuth[0] = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(initialAuth, initialManager)
        );
        assertEq(_authorizer.isAuthorized(1, address(this)), true);
        assertEq(_authorizer.isAuthorized(0, ALBA), true);
        assertEq(_authorizer.isAuthorized(0, address(this)), false);
    }

    //--------------------------------------------------------------------------------------
    // Tests Initialization

    function testInitWithInitialOwners(address[] memory initialAuth) public {
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        address authImpl = address(new RoleAuthorizer());
        RoleAuthorizer testAuthorizer = RoleAuthorizer(Clones.clone(authImpl));

        _validateAuthorizedList(initialAuth);

        testAuthorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );

        assertEq(address(testAuthorizer.proposal()), address(_proposal));

        for (uint i; i < initialAuth.length; ++i) {
            assertEq(testAuthorizer.isAuthorized(0, initialAuth[i]), true);
        }
        assertEq(testAuthorizer.isAuthorized(0, address(this)), false);
        assertEq(
            testAuthorizer.getRoleMemberCount(
                testAuthorizer.PROPOSAL_OWNER_ROLE()
            ),
            initialAuth.length
        );
    }

    function testReinitFails() public {
        //Create a mock new proposal
        Proposal newProposal = Proposal(Clones.clone(address(new Proposal())));

        address[] memory initialAuth = new address[](1);
        initialAuth[0] = address(this);

        vm.expectRevert();
        _authorizer.init(
            IProposal(newProposal), _METADATA, abi.encode(initialAuth)
        );
        assertEq(_authorizer.isAuthorized(0, address(this)), false);
        assertEq(address(_authorizer.proposal()), address(_proposal));
        assertEq(_authorizer.isAuthorized(0, ALBA), true);
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.PROPOSAL_OWNER_ROLE()), 1
        );
    }

    // Test Register Roles



    //--------------------------------------------------------------------------------------
    // Test manually granting and revoking roles as proposal-defined Owner

    function testGrantOwnerRole(address[] memory newAuthorized) public {
        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.PROPOSAL_OWNER_ROLE());

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.grantRole(
                _authorizer.PROPOSAL_OWNER_ROLE(), newAuthorized[i]
            );
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            // These two should be equivalent
            assertEq(
                _authorizer.hasRole(address(_proposal), 0, newAuthorized[i]),
                true
            );
            assertEq(
                _authorizer.hasRole(
                    _authorizer.PROPOSAL_OWNER_ROLE(), newAuthorized[i]
                ),
                true
            );
        }
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.PROPOSAL_OWNER_ROLE()),
            (amountAuth + newAuthorized.length)
        );
    }

    function testRevokeOwnerRole() public {
        //Add Bob as owner
        vm.startPrank(address(ALBA));
        _authorizer.grantRole(_authorizer.PROPOSAL_OWNER_ROLE(), BOB); //Meet your new Manager
        vm.stopPrank();
        assertEq(
            _authorizer.hasRole(_authorizer.PROPOSAL_OWNER_ROLE(), BOB), true
        );

        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.PROPOSAL_OWNER_ROLE());

        vm.startPrank(address(ALBA));
        _authorizer.revokeRole(_authorizer.PROPOSAL_OWNER_ROLE(), ALBA);
        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(_authorizer.PROPOSAL_OWNER_ROLE(), ALBA), false
        );
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.PROPOSAL_OWNER_ROLE()),
            amountAuth - 1
        );
    }

    function testRemoveLastOwnerFails() public {
        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.PROPOSAL_OWNER_ROLE());
        bytes32 ownerRole = _authorizer.PROPOSAL_OWNER_ROLE(); //To correctly time the vm.expectRevert

        vm.expectRevert(
            abi.encodeWithSelector(
                RoleAuthorizer
                    .Module__RoleAuthorizer__OwnerRoleCannotBeEmpty
                    .selector
            )
        );
        vm.prank(address(ALBA));
        _authorizer.revokeRole(ownerRole, ALBA);

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.PROPOSAL_OWNER_ROLE()),
            amountAuth
        );
    }

    function testGrantManagerRole(address[] memory newAuthorized) public {
        // Here we test adding to a role with OWNER as admin

        bytes32 managerRole = _authorizer.generateRoleId(address(_proposal), 1);
        uint amountManagers = _authorizer.getRoleMemberCount(managerRole);

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.grantRole(managerRole, newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(
                _authorizer.hasRole(address(_proposal), 1, newAuthorized[i]),
                true
            );
            assertEq(_authorizer.hasRole(managerRole, newAuthorized[i]), true);
        }
        assertEq(
            _authorizer.getRoleMemberCount(managerRole),
            (amountManagers + newAuthorized.length)
        );
    }

    function testGrantManagerRoleFailsIfNotOwner(address[] memory newAuthorized)
        public
    {
        // Here we test adding to a role that has OWNER as admin while not being OWNER
        bytes32 managerRole = _authorizer.generateRoleId(address(_proposal), 1);

        vm.startPrank(address(ALBA));
        _authorizer.grantRole(managerRole, BOB); //Meet your new Manager
        vm.stopPrank();

        assertEq(_authorizer.hasRole(address(_proposal), 1, BOB), true);
        assertEq(_authorizer.hasRole(managerRole, BOB), true);

        uint amountManagers = _authorizer.getRoleMemberCount(managerRole);

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(BOB));
        for (uint i; i < newAuthorized.length; ++i) {
            vm.expectRevert(); // Just a general revert since AccesControl doesn't have error types
            _authorizer.grantRole(managerRole, newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(
                _authorizer.hasRole(address(_proposal), 1, newAuthorized[i]),
                false
            );
            assertEq(_authorizer.hasRole(managerRole, newAuthorized[i]), false);
        }
        assertEq(_authorizer.getRoleMemberCount(managerRole), amountManagers);
    }

    function testRevokeManagerRole(address[] memory newAuthorized) public {
        // Here we test adding to a role with OWNER as admin

        bytes32 managerRole = _authorizer.generateRoleId(address(_proposal), 1);
        uint amountManagers = _authorizer.getRoleMemberCount(managerRole);

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.grantRole(managerRole, newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(
                _authorizer.hasRole(address(_proposal), 1, newAuthorized[i]),
                true
            );
            assertEq(_authorizer.hasRole(managerRole, newAuthorized[i]), true);
        }
        assertEq(
            _authorizer.getRoleMemberCount(managerRole),
            (amountManagers + newAuthorized.length)
        );

        // Now we remove them all

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.revokeRole(managerRole, newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(
                _authorizer.hasRole(address(_proposal), 1, newAuthorized[i]),
                false
            );
            assertEq(_authorizer.hasRole(managerRole, newAuthorized[i]), false);
        }
        assertEq(_authorizer.getRoleMemberCount(managerRole), amountManagers);
    }

    function testRevokeManagerRoleFailsIfNotOwner(
        address[] memory newAuthorized
    ) public {
        // Here we test adding to a role that has OWNER as admin while not being OWNER
        bytes32 managerRole = _authorizer.generateRoleId(address(_proposal), 1);

        vm.startPrank(address(ALBA));
        _authorizer.grantRole(managerRole, BOB); //Meet your new Manager
        vm.stopPrank();

        assertEq(_authorizer.hasRole(address(_proposal), 1, BOB), true);
        assertEq(_authorizer.hasRole(managerRole, BOB), true);

        uint amountManagers = _authorizer.getRoleMemberCount(managerRole);

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(BOB));
        for (uint i; i < newAuthorized.length; ++i) {
            vm.expectRevert(); // Just a general revert since AccesControl doesn't have error types
            _authorizer.revokeRole(managerRole, newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(
                _authorizer.hasRole(address(_proposal), 1, newAuthorized[i]),
                false
            );
            assertEq(_authorizer.hasRole(managerRole, newAuthorized[i]), false);
        }
        assertEq(_authorizer.getRoleMemberCount(managerRole), amountManagers);
    }




    // Test grantRoleFromModule
    // - Should revert if caller is not a module
    // - Should revert if role does not exist
    // - Should not revert if role is already granted, but not emit events either

    // Test revokeRoleFromModule
    // - Should revert if caller is not a module
    // - Should revert if role does not exist
    // - SHOULD revert if target doesn't have role. (This is different from grantRoleFromModule)


    // =========================================================================
    // Test granting and revokin ADMIN control, and test admin control over module roles
    // Test that only Owner can change admin
    // Test that admin can change nondefined roles
    // Test that admin can change module roles if self managed and if not
    // Test that ADMIN cannot change module roles if admin role was burned

    // Test toggleSelfManagement
    // Test selfManagement gets recognized
    // Test module is using own roles when selfmanaged
    // Test module can correctly return to managed mode

    // Test burnAdminRole
    // Test burnAdmin changes state

    // =========================================================================
    // Test Helper Functions

    function _validateAuthorizedList(address[] memory auths)
        internal
        returns (address[] memory)
    {
        vm.assume(auths.length != 0);
        vm.assume(auths.length < 20);
        assumeValidAuths(auths);

        return auths;
    }
    // Adapted from proposal/helper/TypeSanityHelper.sol

    mapping(address => bool) authorizedCache;

    function assumeValidAuths(address[] memory addrs) public {
        for (uint i; i < addrs.length; ++i) {
            assumeValidAuth(addrs[i]);

            // Assume authorized address unique.
            vm.assume(!authorizedCache[addrs[i]]);

            // Add contributor address to cache.
            authorizedCache[addrs[i]] = true;
        }
    }

    function assumeValidAuth(address a) public view {
        address[] memory invalids = createInvalidAuthorized();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(a != invalids[i]);
        }
    }

    function createInvalidAuthorized() public view returns (address[] memory) {
        address[] memory invalids = new address[](8);

        invalids[0] = address(0);
        invalids[1] = address(_proposal);
        invalids[2] = address(_authorizer);
        invalids[3] = address(_paymentProcessor);
        invalids[4] = address(_token);
        invalids[5] = address(this);
        invalids[6] = ALBA;
        invalids[7] = BOB;

        return invalids;
    }
    // =========================================================================
}
