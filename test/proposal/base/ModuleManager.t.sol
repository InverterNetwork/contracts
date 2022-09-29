// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Helpers
import {FuzzInputChecker} from "test/proposal/helper/FuzzInputChecker.sol";

// Mocks
import {ModuleManagerMock} from
    "test/utils/mocks/proposal/base/ModuleManagerMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

/**
 * Errors library for ModuleManager's custom errors.
 * Enables checking for errors with vm.expectRevert(Errors.<Error>).
 */
library Errors {
    //
    // OpenZeppelin Errors (inherited)
    //
    bytes internal constant OZ__Initializable__NotInitializing =
        bytes("Initializable: contract is not initializing");

    //
    // ModuleManager Errors
    //
    bytes internal constant Proposal__ModuleManager__OnlyCallableByModule = abi
        .encodeWithSignature("Proposal__ModuleManager__OnlyCallableByModule()");

    bytes internal constant Proposal__ModuleManager__AlreadyInitialized =
        abi.encodeWithSignature("Proposal__ModuleManager__AlreadyInitialized()");

    bytes internal constant Proposal__ModuleManager__ExecuteTxFromModuleFailed =
    abi.encodeWithSignature(
        "Proposal__ModuleManager__ExecuteTxFromModuleFailed()"
    );

    bytes internal constant Proposal__ModuleManager__InvalidModuleAddress = abi
        .encodeWithSignature("Proposal__ModuleManager__InvalidModuleAddress()");

    function Proposal__ModuleManager__ModuleAlreadyEnabled(address module)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "Proposal__ModuleManager__ModuleAlreadyEnabled(address)", module
        );
    }
}

contract ModuleManagerTest is Test, FuzzInputChecker {
    // SuT.
    ModuleManagerMock moduleManager;

    function setUp() public {
        moduleManager = new ModuleManagerMock();
    }

    function testInitialization(address[] memory modules) public {
        _assumeValidModules(modules);

        // Initialize ModuleManager.
        moduleManager.init(modules);

        // Check that each module is enabled.
        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            assertTrue(moduleManager.isEnabledModule(module));
        }

        // Check that SENTINEL_MODULE is disabled.
        assertTrue(!moduleManager.isEnabledModule(SENTINEL_MODULE));
    }

    function testInitilizationFailsForInvalidModuleAddress(
        address[] memory modules
    ) public {
        _assumeValidModules(modules);

        // Set first module to address(0).
        modules[0] = address(0);

        vm.expectRevert(Errors.Proposal__ModuleManager__InvalidModuleAddress);
        moduleManager.init(modules);
    }

    function testInitilizationFailsForDuplicateModules(address[] memory modules)
        public
    {
        _assumeValidModules(modules);

        // Duplicate first module.
        vm.assume(modules.length > 1);
        modules[modules.length - 1] = modules[0];

        vm.expectRevert(
            Errors.Proposal__ModuleManager__ModuleAlreadyEnabled(modules[0])
        );
        moduleManager.init(modules);
    }

    function testReinitializationFails(address[] memory modules) public {
        _assumeValidModules(modules);

        moduleManager.init(modules);

        vm.expectRevert(Errors.OZ__Initializable__NotInitializing);
        moduleManager.reinit(modules);
    }

    function testExecuteTxFromModule() public {
        // @todo mp: Add ModuleManager::executeTxFromModule tests.
    }
}
