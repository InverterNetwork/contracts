// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "@unitTest/modules/ModuleTest.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";

import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

// SuT
import {AUT_Roles_v1_Exposed} from
    "@mocks/modules/authorizer/AUT_Roles_v1_Exposed.sol";

// Mocks
import {FundingManagerV1Mock} from
    "@mocks/modules/fundingManager/FundingManagerV1Mock.sol";
import {AuthorizerV1Mock} from "@mocks/modules/authorizer/AuthorizerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "@mocks/modules/paymentProcessor/PaymentProcessorV1Mock.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

// Errors
import {OZErrors} from "@testUtilities/OZErrors.sol";

// External Dependencies
import {IAccessControl} from "@oz/access/IAccessControl.sol";

contract AUT_Roles_v1_Test is ModuleTest {
    ///////////////////////////////////////////////////////////////////////////
    // State

    // SuT
    AUT_Roles_v1_Exposed _authSuT;

    // Constants
    address _initialAdmin = makeAddr("initialAdmin");
    address _bob = makeAddr("Bob");
    address _alice = makeAddr("Alice");

    // Addresses

    // Bob and Alice can Access
    bytes4 _selector1 = bytes4(keccak256("selector1()"));
    // Alice can access
    bytes4 _selector2 = bytes4(keccak256("selector2()"));
    // No Permissions
    bytes4 _selector3 = bytes4(keccak256("selector3()"));
    // Public Role can access
    bytes4 _selector4 = bytes4(keccak256("selector4()"));

    ///////////////////////////////////////////////////////////////////////////
    // Setup

    function setUp() public {
        address impl = address(new AUT_Roles_v1_Exposed());
        _authSuT = AUT_Roles_v1_Exposed(Clones.clone(impl));

        // initiate orchestrator without extra Module
        _setUpOrchestrator();

        _authSuT.init(_orchestrator, _METADATA, abi.encode(_initialAdmin));

        // Change Authorizer of Module Test to SuT
        _orchestrator.initiateSetAuthorizerWithTimelock(
            IAuthorizer_v1(_authSuT)
        );
        vm.warp(72 hours + 1);
        _orchestrator.executeSetAuthorizer(IAuthorizer_v1(_authSuT));
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test Initialization

    /*
    Test: SupportsInterface
    └── Given: The interfaceId is IAuthorizer_v1
        └── When: the function supportsInterface is called
            └── Then: the function should return true
    */
    function testSupportsInterface() public override(ModuleTest) {
        assertTrue(_authSuT.supportsInterface(type(IAuthorizer_v1).interfaceId));
    }

    /*
    Test: Init
    └── When: the function init is called
        └── Then: the function should set the initial admin
    */
    function testInit() public override {
        // Check that the initial Admin is set
        assertTrue(_authSuT.hasRole(_authSuT.getAdminRole(), _initialAdmin));
    }

    /*
    Test: ReinitFails
    └── When: the function init is called after the contract has been initialized
        └── Then: the function should revert
    */
    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        _authSuT.init(_orchestrator, _METADATA, abi.encode(_initialAdmin));
    }
    /////////////////////////////////////////////////////////////////////////////
    // Test Modifier

    //idNotDefaultAdmin
    /*
    Test: idNotDefaultAdmin Modifier
    └── Given: Role ID is the default admin role
        └── When: function with idNotDefaultAdmin modifier is called
            └── Then: the function should revert
     */
    function testIdNotDefaultAdminModifier(bytes32 _givenRoleId) public {
        if (_givenRoleId == _authSuT.DEFAULT_ADMIN_ROLE()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAuthorizer_v1
                        .Module__Authorizer__CannotAddDefaultAdminRole
                        .selector
                )
            );
        }
        _authSuT.idNotDefaultAdminModifier_exposed(_givenRoleId);
    }

    /*
    Test: idExisting Modifier
    └── Given: Role ID is not existing and is not Public Role
        └── When: function with idExisting modifier is called
            └── Then: the function should revert
    */
    function testIdExistingModifier(
        uint _roleIdCounterValue,
        bytes32 _givenRoleId
    ) public {
        _authSuT.changeRoleIdCounter(_roleIdCounterValue);
        if (
            _givenRoleId != _authSuT.PUBLIC_ROLE()
                && uint(_givenRoleId) > _roleIdCounterValue
        ) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAuthorizer_v1
                        .Module__Authorizer__RoleIdNotExisting
                        .selector
                )
            );
        }
        _authSuT.idExistingModifier_exposed(_givenRoleId);
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test External Functions

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter -  Authorization

    /*
    Test: getPermissions
    └── When: getPermissions is called
        └── Then: Return all Role ids that are listed for that function
    */
    function testGetPermissions(
        address target_,
        bytes4 selector_,
        bytes32[] memory permissions_
    ) public {
        for (uint i = 0; i < permissions_.length; i++) {
            _authSuT.addAccessPermission_unrestricted(
                target_, selector_, permissions_[i]
            );
        }
        bytes32[] memory returnedPermissions =
            _authSuT.getPermissions(target_, selector_);
        assertEq(returnedPermissions.length, permissions_.length);
        for (uint i = 0; i < permissions_.length; i++) {
            assertEq(returnedPermissions[i], permissions_[i]);
        }
    }

    /*
    Test: isPermissioned
    └── When: isPermissioned is called
        └── Then: Return true if the roleId is listed for that function
    */
    function testIsPermissioned(
        bytes32 roleId_,
        address target_,
        bytes4 selector_,
        bool isPermissioned_
    ) public {
        if (isPermissioned_) {
            _authSuT.addAccessPermission_unrestricted(
                target_, selector_, roleId_
            );
        }
        assertEq(
            _authSuT.isPermissioned(target_, selector_, roleId_),
            isPermissioned_
        );
    }

    /*
    Test: hasPermission
    ├── Given: Caller has the Default Admin Role
    │   └── When: hasPermission is called
    │       └── Then: Return true
    ├── Given: There are no roleId permissions for the function
    │   └── When: hasPermission is called
    │       └── Then: Return false
    ├── Given: The permissions contain the public role
    │   └── When: hasPermission is called
    │       └── Then: Return true
    └── Given: The caller inhabits one of the roles that have permission
        └── When: hasPermission is called
            └── Then: Return true
    */

    function testHasPermission_CallerHasDefaultAdminRole(uint seed_) public {
        // Create Setup with predetermined roles and function restrictions
        address target = address(uint160(seed_));
        createSetup(target);

        // Select function selector from setup based on seed
        bytes4 selector = selectFunctionSelectorBasedOnSeed(seed_);

        // Check that if the caller has the default admin role, they can call any function
        assertTrue(_authSuT.hasPermission(_initialAdmin, target, selector));
    }

    function testHasPermission_NoPermissionsForFunction(
        uint seed_,
        address caller_
    ) public {
        // Make sure calle does not have the default admin role
        vm.assume(caller_ != _initialAdmin);

        // Create Setup with predetermined roles and function restrictions
        address target = address(uint160(seed_));
        createSetup(target);

        // Select function selector from setup based on seed
        bytes4 selector = selectFunctionSelectorBasedOnSeed(seed_);

        // Check that the function has no permissions
        if (_authSuT.getPermissions(target, selector).length == 0) {
            // If the function has no permissions, the caller should not be able to call the function
            assertFalse(_authSuT.hasPermission(caller_, target, selector));
        }
    }

    function testHasPermission_PermissionIsPublicRole(
        uint seed_,
        address caller_
    ) public {
        // Make sure caller does not have the default admin role
        vm.assume(caller_ != _initialAdmin);

        // Create Setup with predetermined roles and function restrictions
        address target = address(uint160(seed_));
        createSetup(target);

        // Select function selector from setup based on seed
        bytes4 selector = selectFunctionSelectorBasedOnSeed(seed_);

        bytes32[] memory permissions = _authSuT.getPermissions(target, selector);
        for (uint i = 0; i < permissions.length; i++) {
            if (permissions[i] == _authSuT.PUBLIC_ROLE()) {
                assertTrue(_authSuT.hasPermission(caller_, target, selector));
            }
        }
    }

    function testHasPermission_IsNotPublicRole(uint seed_, uint callerSeed_)
        public
    {
        // Fetch caller from seed
        address caller = selectCallerBasedOnSeed(callerSeed_);
        // Make sure caller is not the default admin or Bob or Alice
        vm.assume(caller != _initialAdmin || caller != _bob || caller != _alice);

        // Create Setup with predetermined roles and function restrictions
        address target = address(uint160(seed_));
        createSetup(target);

        // Select function selector from setup based on seed
        bytes4 selector = selectFunctionSelectorBasedOnSeed(seed_);

        bytes32[] memory permissions = _authSuT.getPermissions(target, selector);
        for (uint i = 0; i < permissions.length; i++) {
            // If the caller has the role they should be able to call the function
            if (_authSuT.hasRole(permissions[i], caller)) {
                assertTrue(_authSuT.hasPermission(caller, target, selector));
            }
        }
    }

    // ------------------------------------------------------------------------
    // Getter -  Role Management

    /*
    Test: getAdminRole
    └── When: getAdminRole is called
        └── Then: Return the Admin Role
    */
    function testGetAdminRole() public {
        assertEq(_authSuT.getAdminRole(), _authSuT.DEFAULT_ADMIN_ROLE());
    }

    // ------------------------------------------------------------------------
    // Getter - Out of Order

    // function checkForRole(bytes32 role, address who)
    /*
    Test: checkForRole
    └── When: grantRoleFromModule is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testCheckForRole_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.checkForRole(bytes32(uint(0)), address(0));
    }

    /*
    Test: generateRoleId
    └── When: grantRoleFromModule is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testGenerateRoleId_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.generateRoleId(address(0), bytes32(uint(0)));
    }

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    /*
    Test: addAccessPermission
    ├── Given: Caller does not inhabit the permissioned Role
    │   └── When: addAccessPermission is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is the default admin role
    │   └── When: addAccessPermission is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is not existing
    │   └── When: addAccessPermission is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is existing and not the default admin role
    ├── And: The given roleId has already permission
    │   └── When: addAccessPermission is called
    │       └── Then: Nothing happens
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is existing and not the default admin role
    └── And: The given roleId does not have permission yet
        └── When: addAccessPermission is called
            └── Then: The roleId gains permission
            └── And: An event is emitted
    */

    function testAddAccessPermission_ModifierInPostionChecks() public {
        //permissioned
        vm.expectRevert(
            abi.encodeWithSelector(IModule_v1.Module__NotPermissioned.selector)
        );
        _authSuT.addAccessPermission(address(this), bytes4(0), bytes32(uint(0)));

        //idNotDefaultAdmin(roleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1
                    .Module__Authorizer__CannotAddDefaultAdminRole
                    .selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.addAccessPermission(
            address(this),
            bytes4(0),
            bytes32(uint(0)) //Default Admin Id
        );

        //idExisting(roleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.addAccessPermission(address(this), bytes4(0), bytes32(uint(2)));
    }

    function testAddAccessPermission_PermissionAlreadyExisting(uint seed_)
        public
    {
        // Create All Role Ids
        _authSuT.changeRoleIdCounter(type(uint).max);

        // Create a random lock setup
        (address target, bytes4 selector) =
            createRandomLockRestrictions(seed_, 1);

        // Fetch permission array for comparison
        bytes32[] memory permissions = _authSuT.getPermissions(target, selector);

        // Fetch one of the permissions from the lock
        bytes32 roleIdPermission = permissions[seed_ % permissions.length];

        // Try it again
        vm.prank(_initialAdmin);
        _authSuT.addAccessPermission(target, selector, roleIdPermission);

        // Fetch permission array for comparison
        bytes32[] memory permissionsAfter =
            _authSuT.getPermissions(target, selector);

        // Check that the array length is the same
        assertEq(permissions.length, permissionsAfter.length);
        // Check that the array stayed the same
        for (uint i = 0; i < permissions.length; i++) {
            assertEq(permissions[i], permissionsAfter[i]);
        }
    }

    function testAddAccessPermission_PermissionNotAlreadyExisting(
        uint seed_,
        bytes32 roleId_
    ) public {
        // Make sure roleId_ is not the default admin role or the Public Role
        vm.assume(roleId_ != _authSuT.DEFAULT_ADMIN_ROLE());
        vm.assume(roleId_ != _authSuT.PUBLIC_ROLE());

        // Create All Role Ids
        _authSuT.changeRoleIdCounter(type(uint).max);

        // Create a random lock setup
        (address target, bytes4 selector) =
            createRandomLockRestrictions(seed_, 0);

        // Make sure roleId_ is not part of the function lock
        vm.assume(!_authSuT.isPermissioned(target, selector, roleId_));

        // Fetch permission array for comparison
        bytes32[] memory permissions = _authSuT.getPermissions(target, selector);

        // Check that event is emitted
        vm.expectEmit(true, true, true, true);
        emit IAuthorizer_v1.AccessPermissionAdded(target, selector, roleId_);

        // Add permission to roleId to function lock
        vm.prank(_initialAdmin);
        _authSuT.addAccessPermission(target, selector, roleId_);

        // Fetch permission array for comparison
        bytes32[] memory permissionsAfter =
            _authSuT.getPermissions(target, selector);

        // Check that array length was adapted
        assertEq(permissionsAfter.length, permissions.length + 1);

        // Check that the role is permissioned
        assertTrue(_authSuT.isPermissioned(target, selector, roleId_));
    }

    /*
    Test: removeAccessPermission
    ├── Given: Caller does not inhabit the permissioned Role
    │   └── When: removeAccessPermission is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId not a permissioned
    │   └── When: removeAccessPermission is called
    │       └── Then: Nothing happens
    ├── Given: Caller inhabits the default admin role
    └── And: The given roleId is permissioned
        └── When: removeAccessPermission is called
            └── Then: The permission is removed
            └── And: An event is emitted

    */
    function testRemoveAccessPermission_ModifierInPostionChecks() public {
        //permissioned
        vm.expectRevert(
            abi.encodeWithSelector(IModule_v1.Module__NotPermissioned.selector)
        );
        _authSuT.removeAccessPermission(
            address(this), bytes4(0), bytes32(uint(0))
        );
    }

    function testRemoveAccessPermission_PermissionNotExisting(
        uint seed_,
        bytes32 roleId_
    ) public {
        // Create All Role Ids
        _authSuT.changeRoleIdCounter(type(uint).max);

        // Create a random lock setup
        (address target, bytes4 selector) =
            createRandomLockRestrictions(seed_, 0);

        // Make sure roleId_ is not part of the function lock
        vm.assume(!_authSuT.isPermissioned(target, selector, roleId_));

        // Fetch permission array for comparison
        bytes32[] memory permissions = _authSuT.getPermissions(target, selector);

        // Remove any permission from function lock
        vm.prank(_initialAdmin);
        _authSuT.removeAccessPermission(target, selector, roleId_);

        // Fetch permission array for comparison
        bytes32[] memory permissionsAfter =
            _authSuT.getPermissions(target, selector);

        // Check that array length is the same
        assertEq(permissions.length, permissionsAfter.length);

        // Check that values stayed the same
        for (uint i = 0; i < permissions.length; i++) {
            assertEq(permissions[i], permissionsAfter[i]);
        }
    }

    function testRemoveAccessPermission_PermissionExisting(uint seed_) public {
        // Create All Role Ids
        _authSuT.changeRoleIdCounter(type(uint).max);

        // Create a random lock setup
        (address target, bytes4 selector) =
            createRandomLockRestrictions(seed_, 1);

        // Fetch permission array for comparison
        bytes32[] memory permissions = _authSuT.getPermissions(target, selector);

        // Fetch one of the permissions from the lock
        bytes32 roleIdPermission = permissions[uint(seed_) % permissions.length];

        // Check that event is emitted
        vm.expectEmit(true, true, true, true);
        emit IAuthorizer_v1.AccessPermissionRemoved(
            target, selector, roleIdPermission
        );

        // Remove permission from function lock
        vm.prank(_initialAdmin);
        _authSuT.removeAccessPermission(target, selector, roleIdPermission);

        // Fetch permission array for comparison
        bytes32[] memory permissionsAfter =
            _authSuT.getPermissions(target, selector);

        // Check that array length is one less
        assertEq(permissions.length - 1, permissionsAfter.length);

        // Check that roleId is not permissioned
        assertFalse(_authSuT.isPermissioned(target, selector, roleIdPermission));
    }

    // ------------------------------------------------------------------------
    // Mutating - Role Management

    /*
    Test: createRole
    ├── Given: Caller does not inhabit the permissioned Role
    │   └── When: createRole is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is not existing
    │   └── When: createRole is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    └── And: The given roleId is existing
        └── When: createRole is called
            ├── Then: The role id counter is incremented
            ├── And: The admin for the role is set
            ├── And: An event is emitted
            └── And: The intial members of the role are set
    */

    function testCreateRole_ModifierInPostionChecks() public {
        //permissioned
        vm.expectRevert(
            abi.encodeWithSelector(IModule_v1.Module__NotPermissioned.selector)
        );
        _authSuT.createRole("RoleName", bytes32(uint(0)), new address[](0));

        //idExisting(respectiveAdminRole_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.createRole("RoleName", bytes32(uint(2)), new address[](0));
    }

    function testCreateRole_RoleIdIsExisting(
        string memory roleName_,
        uint seed_,
        address[] memory members_
    ) public {
        // Check that members_ is reasonably sized
        vm.assume(members_.length < 2500);

        // Create random number of permissions between 0 and half uint max
        _authSuT.changeRoleIdCounter(bound(seed_, 0, type(uint).max / 2));

        uint currentRoleIdCounter = _authSuT.getRoleIdCounter();
        bytes32 expectedRoleId = bytes32(currentRoleIdCounter + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit IAuthorizer_v1.RoleCreated(expectedRoleId, roleName_);

        // Create role
        vm.prank(_initialAdmin);
        bytes32 roleId = _authSuT.createRole(
            roleName_, bytes32(bound(seed_, 0, currentRoleIdCounter)), members_
        );

        // Check that roleId is the expected roleId
        assertEq(roleId, expectedRoleId);

        // Check that each member has the role
        for (uint i = 0; i < members_.length; i++) {
            assertTrue(_authSuT.hasRole(roleId, members_[i]));
        }
    }

    /*
    Test: labelRole
    ├── Given: Caller does not inhabit the default admin role
    │   └── When: labelRole is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is not existing
    │   └── When: labelRole is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    └── And: The given roleId is existing
        └── When: labelRole is called
            └── Then: An event is emitted
    */
    function testLabelRole_ModifierInPositionChecks() public {
        //permissioned
        vm.expectRevert(
            abi.encodeWithSelector(IModule_v1.Module__NotPermissioned.selector)
        );
        _authSuT.labelRole(bytes32(uint(0)), "RoleName");

        //idExisting(roleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.labelRole(bytes32(uint(2)), "RoleName");
    }

    function testLabelRole_IdExisting(string memory newRoleName_) public {
        // Create Role
        vm.prank(_initialAdmin);
        bytes32 id =
            _authSuT.createRole("RoleName", bytes32(0), new address[](0));

        // Check that event is emitted
        vm.expectEmit(true, true, true, true);
        emit IAuthorizer_v1.RoleLabeled(id, newRoleName_);

        // Label role
        vm.prank(_initialAdmin);
        _authSuT.labelRole(id, newRoleName_);
    }

    /*
    Test: transferAdminRole
    ├── Given: Caller is not the admin ot the role for which the admin is being transferred
    │   └── When: transferAdminRole is called
    │       └── Then: The function should revert
    ├── Given: Caller is the admin of the role for which the admin is being transferred
    ├── And: The given roleId is not existing
    │   └── When: transferAdminRole is called
    │       └── Then: The function should revert (modifier in position check)
    ├── Given: Caller is the admin of the role for which the admin is being transferred
    ├── And: The given adminRoleId is not existing
    │   └── When: transferAdminRole is called
    │       └── Then: The function should revert (modifier in position check)
    ├── Given: Caller is the admin of the role for which the admin is being transferred
    ├── And: The given roleId is existing
        └── When: transferAdminRole is called
            └── Then: The Admin should be transferred to the new Admin
    */

    function testTransferAdminRole_OnlyRoleAdmin(
        uint seed_,
        bytes32 roleId_,
        bytes32 roleAdmin_
    ) public {
        // Make sure roleId_ is not the default admin or the public role
        vm.assume(uint(roleId_) > 1);
        // make sure that roleAdmin was created before roleId
        vm.assume(uint(roleId_) > uint(roleAdmin_));

        // Create Setup
        // Create random amount of Roles making the next created Role have the given RoleId
        _authSuT.changeRoleIdCounter(uint(roleId_) - 1);
        // Create new Role with given RoleAdmin
        vm.prank(_initialAdmin);
        _authSuT.createRole("RoleName", roleAdmin_, new address[](0));

        // randomize if caller has the admin role or not
        if (seed_ % 2 == 0) {
            vm.prank(_initialAdmin);
            _authSuT.grantRole(roleAdmin_, _bob);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    address(_bob),
                    roleAdmin_
                )
            );
        }
        vm.prank(_bob);
        _authSuT.transferAdminRole(roleId_, roleAdmin_);
    }

    function testTransferAdminRole_ModifierInPositionChecks() public {
        //idExisting(roleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.transferAdminRole(bytes32(uint(2)), bytes32(uint(0)));

        //idExisting(newAdminRoleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.transferAdminRole(bytes32(uint(0)), bytes32(uint(2)));
    }

    function testTransferAdminRole_IdExisting(
        bytes32 roleId_,
        bytes32 newAdminRoleId_
    ) public {
        // make sure that roleAdmin was created before roleId
        vm.assume(uint(roleId_) > uint(newAdminRoleId_));
        // Create Setup
        // Create random amount of Roles making the next created Role have the given RoleId
        _authSuT.changeRoleIdCounter(uint(roleId_) - 1);
        // Create new Role with given RoleAdmin
        vm.prank(_initialAdmin);
        _authSuT.createRole("RoleName", bytes32(0), new address[](0));

        // Call transferAdminRole
        vm.prank(_initialAdmin);
        _authSuT.transferAdminRole(roleId_, newAdminRoleId_);

        // Check that the new Admin Role is the new Admin
        assertEq(_authSuT.getRoleAdmin(roleId_), newAdminRoleId_);
    }

    // burnAdminFromRole

    /*
    Test: burnAdminFromRole
    ├── Given: Caller is not the admin of the role for which the admin is being burned
    │   └── When: burnAdminFromRole is called
    │       └── Then: The function should revert
    ├── Given: Caller is the admin of the role for which the admin is being burned
    ├── And: The given roleId is not existing
    │   └── When: burnAdminFromRole is called
    │       └── Then: The function should revert (modifier in position check)
    ├── Given: Caller is the admin of the role for which the admin is being burned
    └── And: The given roleId is existing
        └── When: burnAdminFromRole is called
            └── Then: The Admin should be burned
    */

    function testBurnAdminFromRole_OnlyRoleAdmin(
        uint seed_,
        bytes32 roleId_,
        bytes32 roleAdmin_
    ) public {
        // Make sure roleId_ is not the default admin or the public role
        vm.assume(uint(roleId_) > 1);
        // make sure that roleAdmin was created before roleId
        vm.assume(uint(roleId_) > uint(roleAdmin_));

        // Create Setup
        // Create random amount of Roles making the next created Role have the given RoleId
        _authSuT.changeRoleIdCounter(uint(roleId_) - 1);
        // Create new Role with given RoleAdmin
        vm.prank(_initialAdmin);
        _authSuT.createRole("RoleName", roleAdmin_, new address[](0));

        // randomize if caller has the admin role or not
        if (seed_ % 2 == 0) {
            vm.prank(_initialAdmin);
            _authSuT.grantRole(roleAdmin_, _bob);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    address(_bob),
                    roleAdmin_
                )
            );
        }
        vm.prank(_bob);
        _authSuT.burnAdminFromRole(roleId_);
    }

    function testBurnAdminFromRole_ModifierInPositionChecks() public {
        //idExisting(roleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.burnAdminFromRole(bytes32(uint(2)));
    }

    function testBurnAdminFromRole_IdExisting(
        bytes32 roleId_,
        bytes32 adminRoleId_
    ) public {
        // make sure that roleAdmin was created before roleId
        vm.assume(uint(roleId_) > uint(adminRoleId_));
        // Create Setup
        // Create random amount of Roles making the next created Role have the given RoleId
        _authSuT.changeRoleIdCounter(uint(roleId_) - 1);
        // Create new Role with given RoleAdmin
        vm.prank(_initialAdmin);
        _authSuT.createRole("RoleName", adminRoleId_, new address[](0));

        // Give Caller the Admin Role
        vm.prank(_initialAdmin);
        _authSuT.grantRole(adminRoleId_, _bob);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit IAuthorizer_v1.RoleAdminBurned(roleId_);

        // Call transferAdminRole
        vm.prank(_bob);
        _authSuT.burnAdminFromRole(roleId_);

        // Check that the new Admin Role is the Burned Admin role
        assertEq(_authSuT.getRoleAdmin(roleId_), _authSuT.BURN_ADMIN_ROLE());
    }

    // ------------------------------------------------------------------------
    // Mutating - Mixed Utility

    /*
    Test: createRoleAndAddAccessPermissions
    ├── Given: Caller does not inhabit the permissioned Role
    │   └── When: createRoleAndAddAccessPermissions is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is not existing
    │   └── When: createRoleAndAddAccessPermissions is called
    │       └── Then: Then it should revert (modifier in position check)
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is existing
    ├── And: The given targets array and the selectors array do not have the same length
    │   └── When: createRoleAndAddAccessPermissions is called
    │       └── Then: Then it should revert
    ├── Given: Caller inhabits the default admin role
    ├── And: The given roleId is existing
    └── And: The given targets array and the selectors array have the same length
        └── When: createRoleAndAddAccessPermissions is called
            └── Then: The role is created
            └── And: The permissions are added to the according function locks
    */
    function testCreateRoleAndAddAccessPermissions_ModifierInPositionCheck()
        public
    {
        //permissioned
        vm.expectRevert(
            abi.encodeWithSelector(IModule_v1.Module__NotPermissioned.selector)
        );
        _authSuT.createRoleAndAddAccessPermissions(
            "RoleName",
            bytes32(uint(0)),
            new address[](0),
            new address[](0),
            new bytes4[][](0)
        );

        //idExisting(respectiveAdminRole_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.createRoleAndAddAccessPermissions(
            "RoleName",
            bytes32(uint(2)),
            new address[](0),
            new address[](0),
            new bytes4[][](0)
        );
    }

    function testCreateRoleAndAddAccessPermissions_RevertWhenArrayLengthsAreDifferent(
        address[] memory targets_,
        bytes4[][] memory selectors_
    ) public {
        // Make sure the arrays have different lengths
        vm.assume(targets_.length != selectors_.length);

        // Invalid Input Length
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__InvalidInputLength.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.createRoleAndAddAccessPermissions(
            "RoleName", bytes32(uint(0)), new address[](0), targets_, selectors_
        );
    }

    //@note This test alone takes up as much time as the others combined. Restricted the number of runs to 20
    /// forge-config: default.fuzz.runs = 20
    function testCreateRoleAndAddAccessPermissions_IdExisting(
        string memory roleName_,
        address[] memory initialMembers_,
        address[] memory targets_,
        bytes4[][] memory selectors_
    ) public {
        // Downsize arrays to reasonable size
        vm.assume(initialMembers_.length < 800); //800
        vm.assume(targets_.length < 75); //75
        vm.assume(selectors_.length <= targets_.length);

        uint selectorLength = selectors_.length;
        for (uint i = 0; i < selectorLength; i++) {
            vm.assume(selectors_[i].length < 50); //50
        }

        // Make sure that selector length and target length are the same
        if (selectorLength < targets_.length) {
            address[] memory temp = new address[](selectorLength);
            for (uint i = 0; i < selectorLength; i++) {
                temp[i] = targets_[i];
            }
            targets_ = temp;
        }

        // Check that the role is created
        vm.expectEmit(true, true, true, true);
        emit IAuthorizer_v1.RoleCreated(bytes32(uint(2)), roleName_);

        vm.prank(_initialAdmin);
        bytes32 roleId = _authSuT.createRoleAndAddAccessPermissions(
            roleName_, bytes32(0), initialMembers_, targets_, selectors_
        );

        // Check that the permissions are added to the function locks
        uint targetLength = targets_.length;
        for (uint i = 0; i < targetLength; i++) {
            for (uint j = 0; j < selectors_[i].length; j++) {
                assertTrue(
                    _authSuT.isPermissioned(
                        targets_[i], selectors_[i][j], roleId
                    )
                );
            }
        }
    }

    // ------------------------------------------------------------------------
    // Mutating - Out of Order

    /*
    Test: grantRoleFromModule
    └── When: grantRoleFromModule is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testGrantRoleFromModule_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.grantRoleFromModule(bytes32(uint(0)), address(0));
    }

    /*
    Test: grantRoleFromModuleBatched
    └── When: grantRoleFromModuleBatched is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testGrantRoleFromModuleBatched_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.grantRoleFromModuleBatched(bytes32(uint(0)), new address[](0));
    }

    /*
    Test: revokeRoleFromModule
    └── When: revokeRoleFromModule is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testRevokeRoleFromModule_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.revokeRoleFromModule(bytes32(uint(0)), address(0));
    }

    /*
    Test: revokeRoleFromModuleBatched
    └── When: revokeRoleFromModuleBatched is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testRevokeRoleFromModuleBatched_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.revokeRoleFromModuleBatched(bytes32(uint(0)), new address[](0));
    }

    /*
    Test: burnAdminFromModuleRole
    └── When: burnAdminFromModuleRole is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testBurnAdminFromModuleRole_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.burnAdminFromModuleRole(bytes32(uint(0)));
    }

    /*
    Test: grantGlobalRole
    └── When: grantGlobalRole is called
        └── Then: The function should revert with Module_FunctionDeprecated
    */
    function testGrantGlobalRole_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.grantGlobalRole(bytes32(uint(0)), address(0));
    }

    /*
    Test: grantGlobalRoleBatched
    └── When: grantGlobalRoleBatched is called
        └── Then: The function should revert with Module_FunctionDeprecated
        */
    function testGrantGlobalRoleBatched_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.grantGlobalRoleBatched(bytes32(uint(0)), new address[](0));
    }

    /*
    Test: revokeGlobalRole
    └── When: revokeGlobalRole is called
        └── Then: The function should revert with Module_FunctionDeprecated
        */
    function testRevokeGlobalRole_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.revokeGlobalRole(bytes32(uint(0)), address(0));
    }

    /*
    Test: revokeGlobalRoleBatched
    └── When: revokeGlobalRoleBatched is called
        └── Then: The function should revert with Module_FunctionDeprecated
        */
    function testRevokeGlobalRoleBatched_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        _authSuT.revokeGlobalRoleBatched(bytes32(uint(0)), new address[](0));
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test Internal Functions

    // ========================================================================
    // Internal Functions

    // ------------------------------------------------------------------------
    // Internal - Upstream Function Implementations

    // function _grantRole(

    /*
    Test: grantRole
    └── Given: The role id is not existing
        └── When: grantRole is called
            └── Then: The call reverts (modifier in position check)
    */
    function testGrantRole_ModifierInPositionCheck() public {
        // idExisting(role)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        vm.prank(_initialAdmin);
        _authSuT.grantRole(bytes32(uint(2)), _bob);
    }

    ///////////////////////////////////////////////////////////////////////////
    // Helper Functions

    // Bob and Alice can Access selctor1
    // Alice can access selector2
    // No permissions in selector3
    // Public Role can access selector46("selector4()"));
    function createSetup(address target_) internal {
        vm.startPrank(_initialAdmin);

        address[] memory targetArray = new address[](1);
        targetArray[0] = target_;

        address[] memory selector1Members = new address[](2);
        selector1Members[0] = _bob;
        selector1Members[1] = _alice;

        address[] memory selector2Members = new address[](1);
        selector2Members[0] = _alice;

        address[] memory selector3Members = new address[](0);

        address[] memory selector4Members = new address[](0);

        bytes4[][] memory selectorArray = new bytes4[][](1);
        bytes4[] memory selector1Array2D = new bytes4[](1);

        selector1Array2D[0] = _selector1;
        selectorArray[0] = selector1Array2D;

        _authSuT.createRoleAndAddAccessPermissions(
            "Selector1Role",
            _authSuT.getAdminRole(),
            selector1Members,
            targetArray,
            selectorArray
        );

        bytes4[] memory selector2Array2D = new bytes4[](1);

        selector2Array2D[0] = _selector2;
        selectorArray[0] = selector2Array2D;

        _authSuT.createRoleAndAddAccessPermissions(
            "Selector2Role",
            _authSuT.getAdminRole(),
            selector2Members,
            targetArray,
            selectorArray
        );

        bytes4[] memory selector3Array2D = new bytes4[](1);

        selector3Array2D[0] = _selector3;
        selectorArray[0] = selector3Array2D;

        _authSuT.createRoleAndAddAccessPermissions(
            "Selector3Role",
            _authSuT.getAdminRole(),
            selector3Members,
            targetArray,
            selectorArray
        );

        bytes4[] memory selector4Array2D = new bytes4[](1);

        selector4Array2D[0] = _selector4;
        selectorArray[0] = selector4Array2D;

        _authSuT.createRoleAndAddAccessPermissions(
            "Selector4Role",
            _authSuT.getAdminRole(),
            selector4Members,
            targetArray,
            selectorArray
        );

        _authSuT.addAccessPermission(
            target_, _selector4, _authSuT.PUBLIC_ROLE()
        );

        vm.stopPrank();
    }

    function selectFunctionSelectorBasedOnSeed(uint seed_)
        internal
        view
        returns (bytes4 selector_)
    {
        if (seed_ % 5 == 0) {
            selector_ = _selector1;
        } else if (seed_ % 5 == 1) {
            selector_ = _selector2;
        } else if (seed_ % 5 == 2) {
            selector_ = _selector3;
        } else if (seed_ % 5 == 3) {
            selector_ = _selector4;
        } else {
            selector_ = bytes4(bytes32(seed_));
        }
    }

    /// @dev     3 Possible callers
    ///          Bob, Alice, or a random address
    ///          Random address can be Bob or Alice or Initial Admin
    function selectCallerBasedOnSeed(uint seed_)
        internal
        view
        returns (address caller_)
    {
        if (seed_ % 3 == 0) {
            caller_ = _bob;
        } else if (seed_ % 3 == 1) {
            caller_ = _alice;
        } else {
            caller_ = address(uint160(seed_));
        }
    }

    /// @dev needs all permissions to be unlocked via _authSuT.changeRoleIdCounter(type(uint).max);
    function createRandomLockRestrictions(
        uint seed_,
        uint minimumPermissionLength_
    ) internal returns (address target_, bytes4 selector_) {
        target_ = address(uint160(seed_));
        selector_ = bytes4(bytes32(seed_));

        uint permissionLength = seed_ % 50;
        if (permissionLength <= minimumPermissionLength_) {
            permissionLength = minimumPermissionLength_;
        }
        uint currentPermissionRoleId = seed_;
        for (uint i = 0; i < permissionLength; i++) {
            // Increment key in a non regular way
            unchecked {
                currentPermissionRoleId = currentPermissionRoleId + i * i;
            }
            // Key cannot be Default Admin Role
            if (currentPermissionRoleId == 0) {
                currentPermissionRoleId = 1;
            }
            // Key cannot be Public Role
            if (currentPermissionRoleId == type(uint).max) {
                currentPermissionRoleId = type(uint).max - 1;
            }
            vm.prank(_initialAdmin);
            _authSuT.addAccessPermission(target_, selector_, bytes32(uint(1)));
        }
    }
}
