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

    enum ModuleRoles {
        ROLE_0,
        ROLE_1
    }

    // Proposal Constants
    uint internal constant _PROPOSAL_ID = 1;
    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public virtual {
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
        assertEq(
            _authorizer.hasRole(
                _authorizer.PROPOSAL_MANAGER_ROLE(), address(this)
            ),
            true
        );
        assertEq(
            _authorizer.hasRole(_authorizer.PROPOSAL_OWNER_ROLE(), ALBA), true
        );
        assertEq(
            _authorizer.hasRole(
                _authorizer.PROPOSAL_OWNER_ROLE(), address(this)
            ),
            false
        );
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

    function testInitWithoutInitialOwners() public {
        //Checks that address list gets correctly stored on initialization if there are no owners given
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        address authImpl = address(new RoleAuthorizer());
        RoleAuthorizer testAuthorizer = RoleAuthorizer(Clones.clone(authImpl));

        address[] memory initialAuth = new address[](0);

        testAuthorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );

        assertEq(address(testAuthorizer.proposal()), address(_proposal));

        assertEq(testAuthorizer.isAuthorized(0, address(this)), true);
        assertEq(
            testAuthorizer.getRoleMemberCount(
                testAuthorizer.PROPOSAL_OWNER_ROLE()
            ),
            1
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
                IRoleAuthorizer
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

        //assertEq(_authorizer.hasRole(address(_proposal), 1, BOB), true);
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
            /* assertEq(
                _authorizer.hasRole(address(_proposal), 1, newAuthorized[i]),
                false
            );*/
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
            assertEq(_authorizer.hasRole(managerRole, newAuthorized[i]), false);
        }
        assertEq(_authorizer.getRoleMemberCount(managerRole), amountManagers);
    }

    // Test grantRoleFromModule
    // - Should revert if caller is not a module
    // - Should not revert if role is already granted, but not emit events either

    function testGrantRoleFromModule() public {
        address newModule = _setupMockSelfManagedModule();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                ALBA
            ),
            false
        );

        vm.prank(newModule);
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), ALBA);

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                ALBA
            ),
            true
        );
    }

    function testGrantRoleFromModuleFailsIfCalledByNonModule() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(address(BOB));
        vm.expectRevert();
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), ALBA);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                ALBA
            ),
            false
        );
    }

    function testGrantRoleFromModuleFailsIfModuleNotInProposal() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(ALBA);
        _proposal.removeModule(newModule);

        vm.prank(newModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRoleAuthorizer.Module__RoleAuthorizer__NotActiveModule.selector,
                newModule
            )
        );
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), ALBA);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                ALBA
            ),
            false
        );
    }

    function testGrantRoleFromModuleFailsIfModuleNotSelfManaged() public {
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);
        _authorizer.toggleSelfManagement();

        vm.expectRevert(
            abi.encodeWithSelector(
                IRoleAuthorizer
                    .Module__RoleAuthorizer__ModuleNotSelfManaged
                    .selector
            )
        );
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), ALBA);

        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                ALBA
            ),
            false
        );
    }

    function testGrantRoleFromModuleIdempotence() public {
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);

        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), ALBA);

        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), ALBA);
        // No reverts happen

        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                ALBA
            ),
            true
        );
    }

    // Test revokeRoleFromModule
    // - Should revert if caller is not a module
    // - Should revert if role does not exist
    // - Should not revert if target doesn't have role.

    function testRevokeRoleFromModule() public {
        address newModule = _setupMockSelfManagedModule();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                BOB
            ),
            false
        );

        vm.prank(newModule);
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), address(BOB));

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                BOB
            ),
            true
        );

        vm.prank(newModule);
        _authorizer.revokeRoleFromModule(
            uint8(ModuleRoles.ROLE_0), address(BOB)
        );

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                BOB
            ),
            false
        );
    }

    function testRevokeRoleFromModuleFailsIfCalledByNonModule() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(address(BOB));
        vm.expectRevert();
        _authorizer.revokeRoleFromModule(uint8(ModuleRoles.ROLE_0), BOB);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                BOB
            ),
            false
        );
    }

    function testRevokeRoleFromModuleFailsIfModuleNotInProposal() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(ALBA);
        _proposal.removeModule(newModule);

        vm.prank(newModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRoleAuthorizer.Module__RoleAuthorizer__NotActiveModule.selector,
                newModule
            )
        );
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), BOB);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                BOB
            ),
            false
        );
    }

    function testRevokeRoleFromModuleFailsIfModuleNotSelfManaged() public {
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);
        _authorizer.toggleSelfManagement();

        vm.expectRevert(
            abi.encodeWithSelector(
                IRoleAuthorizer
                    .Module__RoleAuthorizer__ModuleNotSelfManaged
                    .selector
            )
        );
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), BOB);

        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                BOB
            ),
            false
        );
    }

    function testRevokeRoleFromModuleIdempotence() public {
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);

        _authorizer.revokeRoleFromModule(uint8(ModuleRoles.ROLE_0), BOB);

        _authorizer.revokeRoleFromModule(uint8(ModuleRoles.ROLE_0), BOB);
        // No reverts happen

        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0)),
                BOB
            ),
            false
        );
    }

    // =========================================================================
    // Test granting and revoking ADMIN control, and test admin control over module roles

    function testGrantAdminRole() public {
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));
    }

    function testGrantAdminRoleFailsIfNotOwner() public {
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(BOB);
        vm.expectRevert();
        _authorizer.grantRole(adminRole, ALBA);
        assertFalse(_authorizer.hasRole(adminRole, ALBA));
    }

    // Test that only Owner can change admin
    function testChangeRoleAdminOnModuleRole() public {
        // First, we make BOB admin
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));

        //Then we set up a mock module
        address newModule = _setupMockSelfManagedModule();
        bytes32 roleId =
            _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0));

        // Now we set the OWNER as Role admin
        vm.startPrank(BOB);
        _authorizer.transferAdminRole(roleId, _authorizer.PROPOSAL_OWNER_ROLE());
        vm.stopPrank();

        // ALBA can now freely grant and revoke roles
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.startPrank(ALBA);
        _authorizer.grantRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), true);
        _authorizer.revokeRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), false);
    }

    function testChangeRoleAdminOnModuleRoleFailsIfNotAdmin() public {
        //We set up a mock module
        address newModule = _setupMockSelfManagedModule();

        bytes32 roleId =
            _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0));
        bytes32 ownerRole = _authorizer.PROPOSAL_OWNER_ROLE(); //Buffer this to time revert

        // BOB is not allowed to do this
        vm.startPrank(BOB);
        vm.expectRevert();
        _authorizer.transferAdminRole(roleId, ownerRole);
        vm.stopPrank();
    }

    // Test that admin can change module roles if self managed and if not
    function testAdminIgnoresIfRoleIsSelfManaged() public {
        // First, we make ALBA admin
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, ALBA);
        assertTrue(_authorizer.hasRole(adminRole, ALBA));

        //Then we set up a mock module
        address newModule = _setupMockSelfManagedModule();
        bytes32 roleId =
            _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0));

        // ALBA can now freely grant and revoke roles
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.startPrank(ALBA);
        _authorizer.grantRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), true);
        _authorizer.revokeRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.stopPrank();

        // The module returns to Managed mode
        vm.prank(newModule);

        // ALBA can still freely grant and revoke roles
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.startPrank(ALBA);
        _authorizer.grantRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), true);
        _authorizer.revokeRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.stopPrank();
    }
    // Test that ADMIN cannot change module roles if admin role was burned

    function testAdminCannotModifyRoleIfAdminBurned() public {
        // First, we make BOB admin
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));

        //Then we set up a mock module and buffer the role with burned admin
        address newModule = _setupMockSelfManagedModule();
        bytes32 roleId =
            _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_1));

        // BOB can NOT grant and revoke roles even though he's admin
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.startPrank(BOB);
        vm.expectRevert();
        _authorizer.grantRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.expectRevert();
        _authorizer.revokeRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.stopPrank();
    }

    /*function testOwnerCanStillModifyRoleIfAdminBurnedButInManagedState()
        public
    {
        // First, we make BOB admin
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));

        //Then we set up a mock module and buffer the role with burned admin
        address newModule = _setupMockSelfManagedModule();
        bytes32 roleId =
            _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_1));

        // We return the module to managed state.
        vm.prank(newModule);
        _authorizer.toggleSelfManagement();

        // As seen in the test above BOB can NOT grant and revoke roles even though he's admin
        // BUT: ALBA, as an OWNER, can
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.startPrank(ALBA);
        _authorizer.grantRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), true);
        _authorizer.revokeRole(roleId, BOB);
        assertEq(_authorizer.hasRole(roleId, BOB), false);
        vm.stopPrank();
    }*/

    // Test toggleSelfManagement
    // Test selfManagement gets recognized
    function testToggleSelfManagement() public {
        // we set up a mock module and buffer the role with burned admin
        address newModule = _setupMockSelfManagedModule();

        // As per the genrating function, it starts as self-managed
        assertTrue(_authorizer.selfManagedModules(newModule));
        // We return the module to managed state.
        vm.prank(newModule);
        _authorizer.toggleSelfManagement();

        //Now it isn't self-managed anymore
        assertFalse(_authorizer.selfManagedModules(newModule));
    }
    // Test module is using own roles when selfmanaged

    function testModuleOnlyUsesOwnRolesWhenSelfManaged() public {
        // First, we  set up a modul and authorize BOB
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), BOB);

        // BOB is authorized
        assertTrue(_authorizer.isAuthorized(uint8(ModuleRoles.ROLE_0), BOB));

        // But ALBA, as owner, is not
        assertFalse(_authorizer.isAuthorized(uint8(0), ALBA));

        vm.stopPrank();
    }

    function testModuleOnlyUsesProposalRolesWhenNotSelfManaged() public {
        // First, we  set up a module and authorize BOB
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_0), BOB);

        // BOB is authorized
        assertTrue(_authorizer.isAuthorized(uint8(ModuleRoles.ROLE_0), BOB));

        // We return the module to managed state.
        _authorizer.toggleSelfManagement();

        // BOB is not authorized anymore
        assertFalse(_authorizer.isAuthorized(uint8(0), BOB));

        // But ALBA, as owner, is
        assertTrue(_authorizer.isAuthorized(uint8(0), ALBA));

        vm.stopPrank();
    }
    // Test module can correctly return to managed mode

    function testModuleReturnToManagedMode() public {
        //testModuleOnlyUsesProposalRolesWhenNotSelfManaged implicitly tests this
    }

    // Test the burnAdminRole
    // -> Test burnAdmin changes state
    function testBurnAdminChangesRoleState() public {
        // _setupMockSelfManagedModule implicitly test this
    }
    // -> Test a role with burnt admin cannot be modified by admin

    function testModifyRoleByAdminFailsIfAdminBurned() public {
        // First, we make BOB admin
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));

        //Then we set up a mock module and buffer both roles
        address newModule = _setupMockSelfManagedModule();
        bytes32 roleId_0 =
            _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_0));
        bytes32 roleId_1 =
            _authorizer.generateRoleId(newModule, uint8(ModuleRoles.ROLE_1));

        vm.startPrank(BOB);

        // BOB can modify role 0
        assertEq(_authorizer.hasRole(roleId_0, ALBA), false);
        _authorizer.grantRole(roleId_0, ALBA);
        assertEq(_authorizer.hasRole(roleId_0, ALBA), true);
        _authorizer.revokeRole(roleId_0, ALBA);
        assertEq(_authorizer.hasRole(roleId_0, ALBA), false);

        // But not role 1
        vm.expectRevert();
        _authorizer.grantRole(roleId_1, ALBA);
        assertEq(_authorizer.hasRole(roleId_1, ALBA), false);
        vm.expectRevert();
        _authorizer.revokeRole(roleId_1, ALBA);
        assertEq(_authorizer.hasRole(roleId_1, ALBA), false);
        vm.stopPrank();
    }

    // -> Modules with burnt admin CAN return to managed state
    function testBurnedModuleCorrectlyReturnToManagedState() public {
        // Same as testModuleOnlyUsesProposalRolesWhenNotSelfManaged but with ROLE_1

        // First, we  set up a module and authorize BOB
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_1), BOB);

        // BOB is authorized
        assertTrue(_authorizer.isAuthorized(uint8(ModuleRoles.ROLE_1), BOB));

        // We return the module to managed state.
        _authorizer.toggleSelfManagement();

        // BOB is not authorized anymore
        assertFalse(_authorizer.isAuthorized(uint8(1), BOB));

        // But ALBA, as owner, is (uint8(0) because we are querying her owner role, not the proposal manager role)
        assertTrue(_authorizer.isAuthorized(uint8(0), ALBA));

        vm.stopPrank();
    }

    // =========================================================================
    // Test Helper Functions

    // SetUp ModuleWith Roles.
    // Creates a Mock module and adds it to the proposal with 2 roles:
    // - 1 with default Admin
    // - 1 with burnt admin
    // BOB is member of both roles.
    function _setupMockSelfManagedModule() internal returns (address) {
        ModuleMock mockModule = new ModuleMock();

        vm.prank(ALBA); //We assume ALBA is owner
        _proposal.addModule(address(mockModule));

        vm.startPrank(address(mockModule));
        _authorizer.toggleSelfManagement();

        _authorizer.burnAdminRole(uint8(ModuleRoles.ROLE_1));

        vm.stopPrank();

        bytes32 burntAdmin = _authorizer.getRoleAdmin(
            _authorizer.generateRoleId(
                address(mockModule), uint8(ModuleRoles.ROLE_1)
            )
        );
        assertTrue(burntAdmin == _authorizer.BURN_ADMIN_ROLE());

        return address(mockModule);
    }

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
