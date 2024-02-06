// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {
    RoleAuthorizer,
    IAuthorizer,
    IModule
} from "src/modules/authorizer/RoleAuthorizer.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/interfaces/IERC165.sol";

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

import {IAccessControl} from "@oz/access/IAccessControl.sol";
// Internal Dependencies
import {Orchestrator} from "src/orchestrator/Orchestrator.sol";
// Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";
// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

contract RoleAuthorizerTest is Test {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // Mocks
    RoleAuthorizer _authorizer;
    Orchestrator internal _orchestrator = new Orchestrator();
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    FundingManagerMock _fundingManager = new FundingManagerMock();
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();
    address ALBA = address(0xa1ba); //default authorized person
    address BOB = address(0xb0b); // example person to add

    bytes32 immutable ROLE_0 = "ROLE_0";
    bytes32 immutable ROLE_1 = "ROLE_1";

    // Orchestrator Constants
    uint internal constant _ORCHESTRATOR_ID = 1;
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
        address propImpl = address(new Orchestrator());
        _orchestrator = Orchestrator(Clones.clone(propImpl));
        ModuleMock module = new ModuleMock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        _orchestrator.init(
            _ORCHESTRATOR_ID,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor
        );

        address initialAuth = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IOrchestrator(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, initialManager)
        );

        //console.log(_authorizer.hasRole(_authorizer.getManagerRole(), initialManager));
        assertEq(
            _authorizer.hasRole(_authorizer.getManagerRole(), address(this)),
            true
        );
        //console.log(_authorizer.hasRole(_authorizer.getOwnerRole(), ALBA));
        assertEq(_authorizer.hasRole(_authorizer.getOwnerRole(), ALBA), true);
        //console.log(_authorizer.hasRole(_authorizer.getOwnerRole(), address(this)));
        assertEq(
            _authorizer.hasRole(_authorizer.getOwnerRole(), address(this)),
            false
        );
    }

    //--------------------------------------------------------------------------------------
    // Tests Initialization

    function testSupportsInterface() public {
        assertTrue(_authorizer.supportsInterface(type(IAuthorizer).interfaceId));
    }

    function testInitWithInitialOwner(address initialAuth) public {
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        address authImpl = address(new RoleAuthorizer());
        RoleAuthorizer testAuthorizer = RoleAuthorizer(Clones.clone(authImpl));

        vm.assume(initialAuth != address(0));
        vm.assume(initialAuth != address(this));

        testAuthorizer.init(
            IOrchestrator(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, address(this))
        );

        assertEq(address(testAuthorizer.orchestrator()), address(_orchestrator));

        assertEq(testAuthorizer.hasRole("0x01", initialAuth), true);

        assertEq(testAuthorizer.hasRole("0x01", address(this)), false);
        assertEq(
            testAuthorizer.getRoleMemberCount(testAuthorizer.getOwnerRole()), 1
        );
    }

    function testInitWithoutInitialOwners() public {
        //Checks that address list gets correctly stored on initialization if there are no owners given
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        address authImpl = address(new RoleAuthorizer());
        RoleAuthorizer testAuthorizer = RoleAuthorizer(Clones.clone(authImpl));

        address initialAuth = address(0);

        testAuthorizer.init(
            IOrchestrator(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, address(this))
        );

        assertEq(address(testAuthorizer.orchestrator()), address(_orchestrator));

        assertEq(testAuthorizer.hasRole("0x01", address(this)), true);
        assertEq(
            testAuthorizer.getRoleMemberCount(testAuthorizer.getOwnerRole()), 1
        );
    }

    function testInitWithInitialOwnerSameAsDeployer() public {
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        address authImpl = address(new RoleAuthorizer());
        RoleAuthorizer testAuthorizer = RoleAuthorizer(Clones.clone(authImpl));

        address initialAuth = address(this);

        testAuthorizer.init(
            IOrchestrator(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, address(this))
        );

        assertEq(address(testAuthorizer.orchestrator()), address(_orchestrator));

        assertEq(testAuthorizer.hasRole("0x01", initialAuth), true);

        assertEq(
            testAuthorizer.getRoleMemberCount(testAuthorizer.getOwnerRole()), 1
        );
    }

    function testReinitFails() public {
        //Create a mock new orchestrator
        Orchestrator newOrchestrator =
            Orchestrator(Clones.clone(address(new Orchestrator())));

        address initialOwner = address(this);
        address initialManager = address(this);

        vm.expectRevert();
        _authorizer.init(
            IOrchestrator(newOrchestrator),
            _METADATA,
            abi.encode(initialOwner, initialManager)
        );
        assertEq(_authorizer.hasRole("0x01", address(this)), false);
        assertEq(address(_authorizer.orchestrator()), address(_orchestrator));
        assertEq(_authorizer.hasRole("0x01", ALBA), true);
        assertEq(_authorizer.getRoleMemberCount(_authorizer.getOwnerRole()), 1);
    }

    function testInit2RoleAuthorizer() public {
        // Attempting to call the init2 function with malformed data
        // SHOULD FAIL
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        _authorizer.init2(_orchestrator, abi.encode(123));

        // Calling init2 for the first time with no dependency
        // SHOULD FAIL
        bytes memory dependencyData = abi.encode(hasDependency, dependencies);
        vm.expectRevert(
            IModule.Module__NoDependencyOrMalformedDependencyData.selector
        );
        _authorizer.init2(_orchestrator, dependencyData);

        // Calling init2 for the first time with dependency = true
        // SHOULD PASS
        dependencyData = abi.encode(true, dependencies);
        _authorizer.init2(_orchestrator, dependencyData);

        // Attempting to call the init2 function again.
        // SHOULD FAIL
        vm.expectRevert(IModule.Module__CannotCallInit2Again.selector);
        _authorizer.init2(_orchestrator, dependencyData);
    }

    // Test Register Roles

    //--------------------------------------------------------------------------------------
    // Test manually granting and revoking roles as orchestrator-defined Owner

    function testGrantOwnerRole(address[] memory newAuthorized) public {
        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.getOwnerRole());

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.grantRole(_authorizer.getOwnerRole(), newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(
                _authorizer.hasRole(
                    _authorizer.getOwnerRole(), newAuthorized[i]
                ),
                true
            );
        }
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.getOwnerRole()),
            (amountAuth + newAuthorized.length)
        );
    }

    function testRevokeOwnerRole() public {
        //Add Bob as owner
        vm.startPrank(address(ALBA));
        _authorizer.grantRole(_authorizer.getOwnerRole(), BOB); //Meet your new Manager
        vm.stopPrank();
        assertEq(_authorizer.hasRole(_authorizer.getOwnerRole(), BOB), true);

        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.getOwnerRole());

        vm.startPrank(address(ALBA));
        _authorizer.revokeRole(_authorizer.getOwnerRole(), ALBA);
        vm.stopPrank();

        assertEq(_authorizer.hasRole(_authorizer.getOwnerRole(), ALBA), false);
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.getOwnerRole()),
            amountAuth - 1
        );
    }

    function testRemoveLastOwnerFails() public {
        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.getOwnerRole());
        bytes32 ownerRole = _authorizer.getOwnerRole(); //To correctly time the vm.expectRevert

        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer
                    .Module__RoleAuthorizer__OwnerRoleCannotBeEmpty
                    .selector
            )
        );
        vm.prank(address(ALBA));
        _authorizer.revokeRole(ownerRole, ALBA);

        assertEq(_authorizer.hasRole(ownerRole, ALBA), true);
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.getOwnerRole()),
            amountAuth
        );
    }

    function testGrantManagerRole(address[] memory newAuthorized) public {
        // Here we test adding to a role with OWNER as admin

        bytes32 managerRole = _authorizer.getManagerRole();
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
        bytes32 managerRole = _authorizer.getManagerRole();

        vm.startPrank(address(ALBA));
        _authorizer.grantRole(managerRole, BOB); //Meet your new Manager
        vm.stopPrank();

        //assertEq(_authorizer.hasRole(address(_orchestrator), 1, BOB), true);
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

        bytes32 managerRole = _authorizer.getManagerRole();
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
                _authorizer.hasRole(address(_orchestrator), 1, newAuthorized[i]),
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
        bytes32 managerRole = _authorizer.getManagerRole();

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
                _authorizer.generateRoleId(newModule, ROLE_0), ALBA
            ),
            false
        );

        vm.prank(newModule);
        _authorizer.grantRoleFromModule(ROLE_0, ALBA);

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), ALBA
            ),
            true
        );
    }

    function testGrantRoleFromModuleFailsIfCalledByNonModule() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(address(BOB));
        vm.expectRevert();
        _authorizer.grantRoleFromModule(ROLE_0, ALBA);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), ALBA
            ),
            false
        );
    }

    function testGrantRoleFromModuleFailsIfModuleNotInOrchestrator() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(ALBA);
        _orchestrator.removeModule(newModule);

        vm.prank(newModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer.Module__RoleAuthorizer__NotActiveModule.selector,
                newModule
            )
        );
        _authorizer.grantRoleFromModule(ROLE_0, ALBA);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), ALBA
            ),
            false
        );
    }

    function testGrantRoleFromModuleIdempotence() public {
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);

        _authorizer.grantRoleFromModule(ROLE_0, ALBA);

        _authorizer.grantRoleFromModule(ROLE_0, ALBA);
        // No reverts happen

        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), ALBA
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
                _authorizer.generateRoleId(newModule, ROLE_0), BOB
            ),
            false
        );

        vm.prank(newModule);
        _authorizer.grantRoleFromModule(ROLE_0, address(BOB));

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), BOB
            ),
            true
        );

        vm.prank(newModule);
        _authorizer.revokeRoleFromModule(ROLE_0, address(BOB));

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), BOB
            ),
            false
        );
    }

    function testRevokeRoleFromModuleFailsIfCalledByNonModule() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(address(BOB));
        vm.expectRevert();
        _authorizer.revokeRoleFromModule(ROLE_0, BOB);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), BOB
            ),
            false
        );
    }

    function testRevokeRoleFromModuleFailsIfModuleNotInOrchestrator() public {
        address newModule = _setupMockSelfManagedModule();

        vm.prank(ALBA);
        _orchestrator.removeModule(newModule);

        vm.prank(newModule);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer.Module__RoleAuthorizer__NotActiveModule.selector,
                newModule
            )
        );
        _authorizer.grantRoleFromModule(ROLE_0, BOB);
        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), BOB
            ),
            false
        );
    }

    function testRevokeRoleFromModuleIdempotence() public {
        address newModule = _setupMockSelfManagedModule();

        vm.startPrank(newModule);

        _authorizer.revokeRoleFromModule(ROLE_0, BOB);

        _authorizer.revokeRoleFromModule(ROLE_0, BOB);
        // No reverts happen

        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(newModule, ROLE_0), BOB
            ),
            false
        );
    }

    // Test grant and revoke global roles

    // Grant global roles
    function testGrantGlobalRole() public {
        bytes32 globalRole =
            _authorizer.generateRoleId(address(_orchestrator), bytes32("0x03"));
        vm.prank(ALBA);
        _authorizer.grantGlobalRole(bytes32("0x03"), BOB);
        assertTrue(_authorizer.hasRole(globalRole, BOB));
    }

    function testGrantGlobalRoleFailsIfNotOwner() public {
        bytes32 globalRole =
            _authorizer.generateRoleId(address(_orchestrator), bytes32("0x03"));
        vm.prank(BOB);
        vm.expectRevert();
        _authorizer.grantGlobalRole(bytes32("0x03"), ALBA);
        assertFalse(_authorizer.hasRole(globalRole, ALBA));
    }

    // Revoke  global roles
    function testRevokeGlobalRole() public {
        bytes32 globalRole =
            _authorizer.generateRoleId(address(_orchestrator), bytes32("0x03"));
        vm.startPrank(ALBA);
        _authorizer.grantGlobalRole(bytes32("0x03"), BOB);
        assertTrue(_authorizer.hasRole(globalRole, BOB));

        _authorizer.revokeGlobalRole(bytes32("0x03"), BOB);
        assertEq(_authorizer.hasRole(globalRole, BOB), false);

        vm.stopPrank();
    }

    function testRevokeGlobalRoleFailsIfNotOwner() public {
        bytes32 globalRole =
            _authorizer.generateRoleId(address(_orchestrator), bytes32("0x03"));
        vm.prank(ALBA);
        _authorizer.grantGlobalRole(bytes32("0x03"), BOB);
        assertTrue(_authorizer.hasRole(globalRole, BOB));

        vm.prank(BOB);
        vm.expectRevert();
        _authorizer.revokeGlobalRole(bytes32("0x03"), BOB);
        assertTrue(_authorizer.hasRole(globalRole, BOB));
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
        bytes32 roleId = _authorizer.generateRoleId(newModule, ROLE_0);

        // Now we set the OWNER as Role admin
        vm.startPrank(BOB);
        _authorizer.transferAdminRole(roleId, _authorizer.getOwnerRole());
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

        bytes32 roleId = _authorizer.generateRoleId(newModule, ROLE_0);
        bytes32 ownerRole = _authorizer.getOwnerRole(); //Buffer this to time revert

        // BOB is not allowed to do this
        vm.startPrank(BOB);
        vm.expectRevert();
        _authorizer.transferAdminRole(roleId, ownerRole);
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
        bytes32 roleId = _authorizer.generateRoleId(newModule, ROLE_1);

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

    // Test the burnAdminFromModuleRole
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
        bytes32 roleId_0 = _authorizer.generateRoleId(newModule, ROLE_0);
        bytes32 roleId_1 = _authorizer.generateRoleId(newModule, ROLE_1);

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

    // =========================================================================
    // Test Helper Functions

    // SetUp ModuleWith Roles.
    // Creates a Mock module and adds it to the orchestrator with 2 roles:
    // - 1 with default Admin
    // - 1 with burnt admin
    // BOB is member of both roles.
    function _setupMockSelfManagedModule() internal returns (address) {
        ModuleMock mockModule = new ModuleMock();

        vm.prank(ALBA); //We assume ALBA is owner
        _orchestrator.addModule(address(mockModule));

        vm.startPrank(address(mockModule));
        _authorizer.burnAdminFromModuleRole(ROLE_1);

        vm.stopPrank();

        bytes32 burntAdmin = _authorizer.getRoleAdmin(
            _authorizer.generateRoleId(address(mockModule), ROLE_1)
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
    // Adapted from orchestrator/helper/TypeSanityHelper.sol

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
        invalids[1] = address(_orchestrator);
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
