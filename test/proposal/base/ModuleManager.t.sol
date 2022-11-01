// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Helpers
import {FuzzInputChecker} from "test/proposal/helper/FuzzInputChecker.sol";

// SuT
import {
    ModuleManagerMock,
    IModuleManager
} from "test/utils/mocks/proposal/base/ModuleManagerMock.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleManagerTest is Test, FuzzInputChecker {
    // SuT
    ModuleManagerMock moduleManager;

    function setUp() public {
        moduleManager = new ModuleManagerMock();
    }

    // @todo mp: Event emission tests missing.

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(address[] memory modules) public {
        _assumeValidModules(modules);

        // Initialize ModuleManager.
        moduleManager.init(modules);

        // Check that each module is enabled.
        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            assertTrue(moduleManager.isEnabledModule(module));
        }
    }

    function testReinitFails(address[] memory modules) public {
        _assumeValidModules(modules);

        moduleManager.init(modules);

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        moduleManager.reinit(modules);
    }

    function testInitFailsForInvalidModuleAddress(address[] memory modules)
        public
    {
        _assumeValidModules(modules);

        // Set first module to address(0).
        vm.assume(modules.length >= 1);
        modules[0] = address(0);

        vm.expectRevert(
            IModuleManager
                .Proposal__ModuleManager__InvalidModuleAddress
                .selector
        );
        moduleManager.init(modules);
    }

    function testInitFailsForDuplicateModules(address[] memory modules)
        public
    {
        _assumeValidModules(modules);

        // Duplicate first module.
        vm.assume(modules.length > 1);
        modules[modules.length - 1] = modules[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManager
                    .Proposal__ModuleManager__ModuleAlreadyEnabled
                    .selector,
                modules[0]
            )
        );
        moduleManager.init(modules);
    }

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTxFromModule() public {
        // @todo mp: Add ModuleManager::executeTxFromModule tests.
    }

    //--------------------------------------------------------------------------
    // Tests: Module Management

    function testEnableModule(address module) public {
        _assumeValidModule(module);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), true);

        vm.assume(!moduleManager.isEnabledModule(module));
        moduleManager.enableModule(module);
        assertTrue(moduleManager.isEnabledModule(module));
    }

    function testEnableModuleFailsIfCallerNotAuthorized(
        address module,
        address caller
    ) public {
        _assumeValidModule(module);

        moduleManager.__ModuleManager_setIsAuthorized(caller, false);

        vm.expectRevert(
            IModuleManager.Proposal__ModuleManager__CallerNotAuthorized.selector
        );
        moduleManager.enableModule(module);
    }

    function testEnableModuleFailsForInvalidModuleAddress() public {
        moduleManager.__ModuleManager_setIsAuthorized(address(this), true);

        vm.expectRevert(
            IModuleManager
                .Proposal__ModuleManager__InvalidModuleAddress
                .selector
        );
        moduleManager.enableModule(address(0));
    }

    function testEnableModuleFailsIfModuleAlreadyEnabled(address[] memory modules) public {
        _assumeValidModules(modules);
        vm.assume(modules.length != 0);

        moduleManager.init(modules);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManager
                    .Proposal__ModuleManager__ModuleAlreadyEnabled
                    .selector,
                modules[0]
            )
        );
        moduleManager.enableModule(modules[0]);

    }

    function testDisableModule(address module) public {
        _assumeValidModule(module);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), true);

        address[] memory modules = new address[](1);
        modules[0] = module;
        moduleManager.init(modules);

        assertTrue(moduleManager.isEnabledModule(module));
        moduleManager.disableModule(module);
        assertTrue(!moduleManager.isEnabledModule(module));
    }

    function testDisableModuleFailsIfCallerNotAuthorized(
        address module,
        address caller
    ) public {
        _assumeValidModule(module);

        moduleManager.__ModuleManager_setIsAuthorized(caller, false);

        vm.expectRevert(
            IModuleManager.Proposal__ModuleManager__CallerNotAuthorized.selector
        );
        moduleManager.disableModule(module);
    }

    //--------------------------------------------------------------------------
    // Tests: Module Access Control

    function testGrantRole(address module, bytes32 role, address account)
        public
    {
        _assumeValidModule(module);

        address[] memory modules = new address[](1);
        modules[0] = module;
        moduleManager.init(modules);

        vm.prank(module);
        moduleManager.grantRole(role, account);

        assertTrue(moduleManager.hasRole(module, role, account));
    }

    function testGrantRoleFailsIfCallerNotModule(
        address caller,
        address module,
        bytes32 role,
        address account
    ) public {
        _assumeValidModule(module);
        vm.assume(caller != module);

        address[] memory modules = new address[](1);
        modules[0] = module;
        moduleManager.init(modules);

        vm.prank(caller);
        vm.expectRevert(
            IModuleManager
                .Proposal__ModuleManager__OnlyCallableByModule
                .selector
        );
        moduleManager.grantRole(role, account);
    }

    function testRevokeRole(address module, bytes32 role, address account)
        public
    {
        _assumeValidModule(module);

        address[] memory modules = new address[](1);
        modules[0] = module;
        moduleManager.init(modules);

        vm.startPrank(module);
        {
            moduleManager.grantRole(role, account);
            moduleManager.revokeRole(role, account);
        }
        vm.stopPrank();

        assertTrue(!moduleManager.hasRole(module, role, account));
    }

    function testRevokeRoleFailsIfCallerNotModule(
        address caller,
        address module,
        bytes32 role,
        address account
    ) public {
        _assumeValidModule(module);
        vm.assume(caller != module);

        address[] memory modules = new address[](1);
        modules[0] = module;
        moduleManager.init(modules);

        vm.prank(caller);
        vm.expectRevert(
            IModuleManager
                .Proposal__ModuleManager__OnlyCallableByModule
                .selector
        );
        moduleManager.revokeRole(role, account);
    }

    function testRenounceRole(address module, bytes32 role, address account)
        public
    {
        _assumeValidModule(module);

        address[] memory modules = new address[](1);
        modules[0] = module;
        moduleManager.init(modules);

        vm.prank(module);
        moduleManager.grantRole(role, account);

        vm.prank(account);
        moduleManager.renounceRole(module, role);

        assertTrue(!moduleManager.hasRole(module, role, account));
    }

    function testRolesDisabledIfModuleDisabled(
        address module,
        bytes32 role,
        address account
    ) public {
        _assumeValidModule(module);

        address[] memory modules = new address[](1);
        modules[0] = module;
        moduleManager.init(modules);

        vm.prank(module);
        moduleManager.grantRole(role, account);

        // Disable module.
        moduleManager.__ModuleManager_setIsAuthorized(address(this), true);
        moduleManager.disableModule(module);

        assertTrue(!moduleManager.hasRole(module, role, account));
    }
}
