// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {
    AUT_Roles_v1,
    IAuthorizer_v1,
    IModule_v1
} from "@aut/role/AUT_Roles_v1.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC165} from "@oz/interfaces/IERC165.sol";

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

import {IAccessControl} from "@oz/access/IAccessControl.sol";
// Internal Dependencies
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";
// Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";
// Mocks
import {ERC20Mock} from "@mock/external/token/ERC20Mock.sol";
import {ModuleV1Mock} from "@mock/modules/base/ModuleV1Mock.sol";
import {FundingManagerV1Mock} from
    "@mock/modules/fundingManager/FundingManagerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "@mock/modules/paymentProcessor/PaymentProcessorV1Mock.sol";
import {GovernorV1Mock} from "@mock/external/governance/GovernorV1Mock.sol";
import {ModuleFactoryV1Mock} from "@mock/factories/ModuleFactoryV1Mock.sol";

contract AUT_RolesV1Test is Test {
    // Mocks
    AUT_Roles_v1 _authorizer;
    Orchestrator_v1 internal _orchestrator = new Orchestrator_v1(address(0));
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    FundingManagerV1Mock _fundingManager = new FundingManagerV1Mock();
    PaymentProcessorV1Mock _paymentProcessor = new PaymentProcessorV1Mock();
    GovernorV1Mock internal _governor = new GovernorV1Mock();
    ModuleFactoryV1Mock internal _moduleFactory = new ModuleFactoryV1Mock();
    TransactionForwarder_v1 _forwarder = new TransactionForwarder_v1();
    address ALBA = address(0xa1ba); // default authorized person
    address BOB = address(0xb0b); // example person to add

    bytes32 immutable ROLE_0 = "ROLE_0";
    bytes32 immutable ROLE_1 = "ROLE_1";

    // Orchestrator_v1 Constants
    uint internal constant _ORCHESTRATOR_ID = 1;
    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    uint constant PATCH_VERSION = 0;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule_v1.Metadata _METADATA = IModule_v1.Metadata(
        MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION, URL, TITLE
    );

    //--------------------------------------------------------------------------
    // Events

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(
        bytes32 indexed role,
        bytes32 indexed previousAdminRole,
        bytes32 indexed newAdminRole
    );

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
     */
    event RoleGranted(
        bytes32 indexed role, address indexed account, address indexed sender
    );

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(
        bytes32 indexed role, address indexed account, address indexed sender
    );

    function setUp() public virtual {
        address authImpl = address(new AUT_Roles_v1());
        _authorizer = AUT_Roles_v1(Clones.clone(authImpl));
        address propImpl = address(new Orchestrator_v1(address(_forwarder)));
        _orchestrator = Orchestrator_v1(Clones.clone(propImpl));
        ModuleV1Mock module = new ModuleV1Mock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        _orchestrator.init(
            _ORCHESTRATOR_ID,
            address(_moduleFactory),
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor,
            _governor
        );

        address initialAuth = ALBA;

        _authorizer.init(
            IOrchestrator_v1(_orchestrator), _METADATA, abi.encode(initialAuth)
        );

        // console.log(_authorizer.hasRole(_authorizer.getAdminRole(), ALBA));
        assertEq(_authorizer.hasRole(_authorizer.getAdminRole(), ALBA), true);
        // console.log(_authorizer.hasRole(_authorizer.getAdminRole(), address(this)));
        assertEq(
            _authorizer.hasRole(_authorizer.getAdminRole(), address(this)),
            false
        );
    }

    //--------------------------------------------------------------------------------
    // Tests Initialization

    function testSupportsInterface() public {
        assertTrue(
            _authorizer.supportsInterface(type(IAuthorizer_v1).interfaceId)
        );
    }

    function testInitWithInitialAdmin(address initialAuth) public {
        // Checks that address list gets correctly stored on initialization
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        address authImpl = address(new AUT_Roles_v1());
        AUT_Roles_v1 testAuthorizer = AUT_Roles_v1(Clones.clone(authImpl));

        vm.assume(initialAuth != address(0));
        vm.assume(initialAuth != address(this));
        vm.assume(initialAuth != address(_orchestrator));

        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, address(this))
        );

        assertEq(
            testAuthorizer.getRoleAdmin(testAuthorizer.BURN_ADMIN_ROLE()),
            testAuthorizer.BURN_ADMIN_ROLE()
        );

        assertEq(address(testAuthorizer.orchestrator()), address(_orchestrator));

        assertEq(
            testAuthorizer.hasRole(testAuthorizer.getAdminRole(), initialAuth),
            true
        );

        assertEq(
            testAuthorizer.hasRole(testAuthorizer.getAdminRole(), address(this)),
            false
        );
        assertEq(
            testAuthorizer.getRoleMemberCount(testAuthorizer.getAdminRole()), 1
        );
    }

    function testInitWithoutInitialAdmins() public {
        // Checks that address list gets correctly stored on initialization if there are no admins given
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        address authImpl = address(new AUT_Roles_v1());
        AUT_Roles_v1 testAuthorizer = AUT_Roles_v1(Clones.clone(authImpl));

        address initialAuth = address(0);

        vm.expectRevert(
            IAuthorizer_v1.Module__Authorizer__InvalidInitialAdmin.selector
        );

        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, address(this))
        );

        assertEq(
            testAuthorizer.getRoleMemberCount(testAuthorizer.getAdminRole()), 0
        );
    }

    function testInitWithInitialAdminSameAsDeployer() public {
        // Checks that address list gets correctly stored on initialization
        // We "reuse" the orchestrator created in the setup, but the orchestrator doesn't know about this new authorizer.

        address authImpl = address(new AUT_Roles_v1());
        AUT_Roles_v1 testAuthorizer = AUT_Roles_v1(Clones.clone(authImpl));

        address initialAuth = address(this);

        testAuthorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, address(this))
        );

        assertEq(
            testAuthorizer.getRoleAdmin(testAuthorizer.BURN_ADMIN_ROLE()),
            testAuthorizer.BURN_ADMIN_ROLE()
        );

        assertEq(address(testAuthorizer.orchestrator()), address(_orchestrator));

        assertEq(
            testAuthorizer.hasRole(testAuthorizer.getAdminRole(), initialAuth),
            true
        );

        assertEq(
            testAuthorizer.getRoleMemberCount(testAuthorizer.getAdminRole()), 1
        );
    }

    function testReinitFails() public {
        // Create a mock new orchestrator
        Orchestrator_v1 newOrchestrator = Orchestrator_v1(
            Clones.clone(address(new Orchestrator_v1(address(0))))
        );

        address initialAdmin = address(this);

        vm.expectRevert();
        _authorizer.init(
            IOrchestrator_v1(newOrchestrator),
            _METADATA,
            abi.encode(initialAdmin)
        );
        assertEq(
            _authorizer.hasRole(_authorizer.getAdminRole(), address(this)),
            false
        );
        assertEq(address(_authorizer.orchestrator()), address(_orchestrator));
        assertEq(_authorizer.hasRole(_authorizer.getAdminRole(), ALBA), true);
        assertEq(_authorizer.getRoleMemberCount(_authorizer.getAdminRole()), 1);
    }

    // Test Register Roles

    //--------------------------------------------------------------------------------
    // Test manually granting and revoking roles as orchestrator-defined Admin

    function testGrantAdminRole(address[] memory newAuthorized) public {
        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.getAdminRole());

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit RoleGranted(
                _authorizer.getAdminRole(), newAuthorized[i], address(ALBA)
            );

            _authorizer.grantRole(_authorizer.getAdminRole(), newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(
                _authorizer.hasRole(
                    _authorizer.getAdminRole(), newAuthorized[i]
                ),
                true
            );
        }
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.getAdminRole()),
            (amountAuth + newAuthorized.length)
        );
    }

    function testGrantAdminRoleFailsIfOrchestratorWillBeAdmin() public {
        vm.startPrank(address(ALBA));

        bytes32 adminRole = _authorizer.getAdminRole();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1
                    .Module__Authorizer__OrchestratorCannotHaveAdminRole
                    .selector
            )
        );

        _authorizer.grantRole(adminRole, address(_orchestrator));

        vm.stopPrank();
    }

    function testRevokeAdminRole() public {
        // Add Bob as admin
        vm.startPrank(address(ALBA));
        _authorizer.grantRole(_authorizer.getAdminRole(), BOB); // Meet your new Manager
        vm.stopPrank();
        assertEq(_authorizer.hasRole(_authorizer.getAdminRole(), BOB), true);

        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.getAdminRole());

        vm.startPrank(address(ALBA));

        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(
            _authorizer.getAdminRole(), address(ALBA), address(ALBA)
        );

        _authorizer.revokeRole(_authorizer.getAdminRole(), ALBA);
        vm.stopPrank();

        assertEq(_authorizer.hasRole(_authorizer.getAdminRole(), ALBA), false);
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.getAdminRole()),
            amountAuth - 1
        );
    }

    function testRemoveLastAdminFails() public {
        uint amountAuth =
            _authorizer.getRoleMemberCount(_authorizer.getAdminRole());
        bytes32 adminRole = _authorizer.getAdminRole(); // To correctly time the vm.expectRevert

        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1
                    .Module__Authorizer__AdminRoleCannotBeEmpty
                    .selector
            )
        );
        vm.prank(address(ALBA));
        _authorizer.revokeRole(adminRole, ALBA);

        assertEq(_authorizer.hasRole(adminRole, ALBA), true);
        assertEq(
            _authorizer.getRoleMemberCount(_authorizer.getAdminRole()),
            amountAuth
        );
    }

    // =========================================================================
    // Test granting and revoking ADMIN control, and test admin control over module roles

    function testGrantAdminRole() public {
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(adminRole, BOB, ALBA);

        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));
    }

    function testGrantAdminRoleFailsIfNotAdmin() public {
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        address COBIE = address(0xC0B1E);

        vm.prank(BOB);
        vm.expectRevert();
        _authorizer.grantRole(adminRole, COBIE);
        assertFalse(_authorizer.hasRole(adminRole, COBIE));
    }

    // Test that only Admin can change admin
    function testChangeRoleAdminOnModuleRole() public {
        // First, we make BOB admin
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));

        // Then we set up a mock module
        address newModule = _setupMockSelfManagedModule();
        bytes32 roleId = _authorizer.generateRoleId(newModule, ROLE_0);

        // Now we set the OWNER as Role admin
        vm.startPrank(BOB);
        _authorizer.transferAdminRole(roleId, _authorizer.getAdminRole());
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
        // We set up a mock module
        address newModule = _setupMockSelfManagedModule();

        bytes32 roleId = _authorizer.generateRoleId(newModule, ROLE_0);
        bytes32 adminRole = _authorizer.getAdminRole(); // Buffer this to time revert

        // BOB is not allowed to do this
        vm.startPrank(BOB);
        vm.expectRevert();
        _authorizer.transferAdminRole(roleId, adminRole);
        vm.stopPrank();
    }

    // Test that ADMIN cannot change module roles if admin role was burned

    function testAdminCannotModifyRoleIfAdminBurned() public {
        // First, we make BOB admin
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, BOB);
        assertTrue(_authorizer.hasRole(adminRole, BOB));

        // Then we set up a mock module and buffer the role with burned admin
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

        // Then we set up a mock module and buffer both roles
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
        ModuleV1Mock mockModule = new ModuleV1Mock();

        vm.startPrank(ALBA); // We assume ALBA is admin
        _orchestrator.initiateAddModuleWithTimelock(address(mockModule));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(mockModule));
        vm.stopPrank();
        vm.startPrank(address(mockModule));

        vm.expectEmit(true, true, true, true);
        emit RoleAdminChanged(
            _authorizer.generateRoleId(address(mockModule), ROLE_1),
            bytes32(0x00),
            _authorizer.BURN_ADMIN_ROLE()
        );

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
