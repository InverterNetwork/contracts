pragma solidity 0.8.23;

// SuT
import {Test} from "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Dependencies
import {IAccessManaged} from "@oz/access/manager/IAccessManaged.sol";
import {IAccessManager} from "@oz/access/manager/IAccessManager.sol";

// Internal Dependencies
import {IModule_v2, IOrchestrator_v2} from "src/modules/base/IModule_v2.sol";
import {IAuthorizer_v2, AUT_Roles_v2} from "@aut/role/AUT_Roles_v2.sol";

// Mocks
import {Module_v2Mock} from "test/utils/mocks/modules/base/Module_v2Mock.sol";
import {Orchestrator_v2Mock} from
    "test/utils/mocks/orchestrator/Orchestrator_v2Mock.sol";

contract AUT_Roles_v2Test is Test {
    Orchestrator_v2Mock _orchestrator = new Orchestrator_v2Mock(address(0));
    AUT_Roles_v2 _authorizer;
    Module_v2Mock module;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    uint constant PATCH_VERSION = 0;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule_v2.Metadata _METADATA = IModule_v2.Metadata(
        MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION, URL, TITLE
    );

    function setUp() public virtual {
        _authorizer = new AUT_Roles_v2();
        module = new Module_v2Mock();

        address authImpl = address(new AUT_Roles_v2());
        _authorizer = AUT_Roles_v2(Clones.clone(authImpl));

        address moduleImpl = address(new Module_v2Mock());
        module = Module_v2Mock(Clones.clone(moduleImpl));

        _orchestrator.overrideSetAuthorizer(_authorizer);

        _authorizer.init(
            IOrchestrator_v2(_orchestrator),
            _METADATA,
            abi.encode(owner) // make the owner address the initial admin
        );

        module.init(IOrchestrator_v2(_orchestrator), _METADATA, bytes("")); // make this address the initial admin
    }

    function testRestrictedModifier(address caller) public {
        if (caller != address(owner)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessManaged.AccessManagedUnauthorized.selector, caller
                )
            );
        }

        vm.prank(caller);
        module.doSmth(0);
    }

    // Label Role Name to id
    function testLabelRole() public {
        //Create the Role Subadmin and check for proper events
        uint64 expectedRoleId = _authorizer.getCurrentRoleId();

        vm.expectEmit(true, true, true, true);
        emit IAccessManager.RoleLabel(expectedRoleId, "SubAdmin");

        vm.prank(owner);
        _authorizer.createRole("SubAdmin");
    }

    // Only allow functions to be called for created Roles
    function testOnlyAllowFunctionsToBeCalledForCreatedRoles() public {
        // Fetch the id that will be created next
        // That id should not be created yet
        uint64 expectedRoleId = _authorizer.getCurrentRoleId();

        // Fetch the function selector of the target function
        bytes4 functionSelector = module.doSmth.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = functionSelector;

        // Expect revert because the role is not created
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v2.Authorizer_v2__RoleIdNotCreated.selector
            )
        );

        vm.prank(owner);
        _authorizer.setTargetFunctionRole(
            address(module), selectors, expectedRoleId
        );

        // Create the according roleId
        vm.prank(owner);
        _authorizer.createRole("SubAdmin");

        // Now it should be possible to call the function
        vm.prank(owner);
        _authorizer.setTargetFunctionRole(
            address(module), selectors, expectedRoleId
        );
    }

    // Let Workflow owners define the restrictions of the functions themselves
    function testOwnersDefineRestrictions() public {
        //Create the Role Subadmin
        uint64 expectedRoleId = _authorizer.getCurrentRoleId();

        vm.prank(owner);
        _authorizer.createRole("SubAdmin");

        // Fetch the function selector of the target function
        bytes4 functionSelector = module.doSmth.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = functionSelector;

        // Set the Target function to be accessible form the newly created role
        vm.prank(owner);
        _authorizer.setTargetFunctionRole(
            address(module), selectors, expectedRoleId
        );

        // Check that bob cant call doSmth, because he doesnt have the rights yet
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessManaged.AccessManagedUnauthorized.selector, bob
            )
        );
        vm.prank(bob);
        module.doSmth(0);

        // Grant the role
        vm.prank(owner);
        _authorizer.grantRole(expectedRoleId, bob, 0);

        // Bob should be able to call the function now
        vm.prank(bob);
        module.doSmth(0);
    }

    // Public Roles
    function testSettingPublicAccess(address randomCaller) public {
        vm.assume(randomCaller != address(_authorizer));

        // Check that bob cant call doSmth, because he doesnt have the rights yet
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessManaged.AccessManagedUnauthorized.selector, bob
            )
        );
        vm.prank(bob);
        module.doSmth(0);

        // Fetch the function selector of the target function
        bytes4 functionSelector = module.doSmth.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = functionSelector;

        // Set the Target function to be accessible form the newly created role
        vm.prank(owner);
        //@todo should this be a different function? This would mean we have to check every time if the roleid is the public role or not
        _authorizer.setTargetFunctionRole(
            address(module),
            selectors,
            type(uint64).max // This is the public role id
        );

        // Bob should be able to call the function now
        vm.prank(bob);
        module.doSmth(0);

        // Random address should also be able to call the function now
        vm.prank(randomCaller);
        module.doSmth(0);
    }

    // Hierarchical Roles //@ŧodo We dont have the full definition of what this entails
    function testHierarchicalRoles() public {
        // Create the Role Subadmin
        uint64 subAdminRoleId = _authorizer.getCurrentRoleId();
        vm.prank(owner);
        _authorizer.createRole("SubAdmin");

        // Create the Role User
        uint64 userRoleId = _authorizer.getCurrentRoleId();
        vm.prank(owner);
        _authorizer.createRole("User");

        // Make the SubAdmin able to grant the Role user
        vm.prank(owner);
        _authorizer.setRoleAdmin(userRoleId, subAdminRoleId);

        // Grant the role
        vm.prank(owner);
        _authorizer.grantRole(subAdminRoleId, bob, 0);

        // Bob should be able to grant the Role user now
        vm.prank(bob);
        _authorizer.grantRole(userRoleId, alice, 0);
    }

    // Renounce all Authorization
    function testRenounceAllAuthorization() public {
        // The owner should be able to call the function
        vm.prank(owner);
        module.doSmth(0);

        // The owner renounces its own role
        vm.prank(owner);
        _authorizer.renounceRole(0, owner);

        // owner should no longer be able to call the function
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessManaged.AccessManagedUnauthorized.selector, owner
            )
        );
        vm.prank(owner);
        module.doSmth(0);
    }

    // Tranfer your own Role to another address //@todo this is not possible right now. What would be the restrictions for that?
    function testTransferRole() public {
        // Create the Role User
        uint64 userRoleId = _authorizer.getCurrentRoleId();
        vm.prank(owner);
        _authorizer.createRole("User");

        // Grant the role
        vm.prank(owner);
        _authorizer.grantRole(userRoleId, bob, 0);
    }

    // Start directly with roles in a module
    function testStartDirectlyWithRolesInAModule() public {
        //@todo
    }

    // Forward has role to external contracts // @todo Is this relevant?
    // Module Roles vs Global Roles // @todo Is this relevant?
}
