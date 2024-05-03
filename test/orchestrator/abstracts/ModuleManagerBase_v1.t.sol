// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    ModuleManagerBaseV1Mock,
    IModuleManagerBase_v1
} from "test/utils/mocks/orchestrator/abstracts/ModuleManagerBaseV1Mock.sol";

// Mocks
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Helper
import {TypeSanityHelper} from "test/orchestrator/helper/TypeSanityHelper.sol";

contract ModuleManagerBaseV1Test is Test {
    // SuT
    ModuleManagerBaseV1Mock moduleManager;

    // Helper
    TypeSanityHelper types;

    // Constants
    uint MAX_MODULES = 128;
    address[] EMPTY_LIST = new address[](0);
    uint internal timelock;

    // Events copied from SuT.
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    event ModuleRoleGranted(
        address indexed module, bytes32 indexed role, address indexed account
    );
    event ModuleRoleRevoked(
        address indexed module, bytes32 indexed role, address indexed account
    );
    event ModuleUpdateCanceled(address module);

    function setUp() public {
        moduleManager = new ModuleManagerBaseV1Mock(address(0));
        moduleManager.init(EMPTY_LIST);

        types = new TypeSanityHelper(address(moduleManager));

        moduleManager.__ModuleManager_setIsAuthorized(address(this), true);
        timelock = moduleManager.MODULE_UPDATE_TIMELOCK();
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(address[] memory modules) public {
        moduleManager = new ModuleManagerBaseV1Mock(address(0));
        types = new TypeSanityHelper(address(moduleManager));

        types.assumeValidModules(modules);

        if (modules.length > (MAX_MODULES - 3)) {
            vm.expectRevert(
                IModuleManagerBase_v1
                    .ModuleManagerBase__ModuleAmountOverLimits
                    .selector
            );

            moduleManager.init(modules);
        } else {
            moduleManager.init(modules);

            // List of modules should be size of modules array.
            address[] memory modulesAdded = moduleManager.listModules();
            assertEq(modulesAdded.length, modules.length);

            // Each module should be added.
            for (uint i; i < modules.length; ++i) {
                assertTrue(moduleManager.isModule(modules[i]));
            }
        }
    }

    function testReinitFails() public {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        moduleManager.init(EMPTY_LIST);
    }

    function testInitFailsForNonInitializerFunction() public {
        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        moduleManager.initNoInitializer(EMPTY_LIST);
    }

    function testInitFailsForInvalidModules() public {
        moduleManager = new ModuleManagerBaseV1Mock(address(0));
        types = new TypeSanityHelper(address(moduleManager));

        address[] memory invalids = types.createInvalidModules();

        address[] memory modules = new address[](1);

        for (uint i; i < invalids.length; ++i) {
            modules[0] = invalids[i];

            vm.expectRevert(
                IModuleManagerBase_v1
                    .ModuleManagerBase__InvalidModuleAddress
                    .selector
            );
            moduleManager.init(modules);
        }
    }

    function testInitFailsIfModuleAddedTwice() public {
        moduleManager = new ModuleManagerBaseV1Mock(address(0));
        types = new TypeSanityHelper(address(moduleManager));

        address[] memory modules = new address[](2);
        modules[0] = address(0xCAFE);
        modules[1] = address(0xCAFE);

        vm.expectRevert(
            IModuleManagerBase_v1.ModuleManagerBase__IsModule.selector
        );
        moduleManager.init(modules);
    }

    function testInitFailsForTooManyModules(address[] memory modules) public {
        vm.assume(modules.length > MAX_MODULES);

        //we don't need to check for validity since it should revert before

        moduleManager = new ModuleManagerBaseV1Mock(address(0));
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleAmountOverLimits
                .selector
        );
        moduleManager.init(modules);
    }

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTxFromModuleOnlyCallableByModule() public {
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__OnlyCallableByModule
                .selector
        );
        moduleManager.executeTxFromModule(address(this), bytes(""));
    }

    function testExecuteTxFromModuleViaCall() public {
        address module = address(0xCAFE);

        moduleManager.initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.executeAddModule(module);

        bool ok_;
        bytes memory returnData;

        vm.prank(module);
        (ok_, returnData) = moduleManager.executeTxFromModule(
            address(this), abi.encodeWithSignature("ok()")
        );

        assertTrue(ok_);
        assertTrue(abi.decode(returnData, (bool)));
    }

    function testExecuteTxFromModuleViaCallFails() public {
        address module = address(0xCAFE);
        moduleManager.initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.executeAddModule(module);

        bool ok_;
        bytes memory returnData;

        vm.prank(module);
        (ok_, returnData) = moduleManager.executeTxFromModule(
            address(this), abi.encodeWithSignature("fails()")
        );

        assertTrue(!ok_);
    }

    function ok() public pure returns (bool) {
        return true;
    }

    function fails() public pure {
        revert("failed");
    }

    //--------------------------------------------------------------------------
    // Tests: Module Management

    //----------------------------------
    // Tests: addModules()

    function testAddModule(address[] memory whos) public {
        vm.assume(whos.length <= MAX_MODULES);
        types.assumeValidModules(whos);
        bool timelockActive;

        for (uint i; i < whos.length; ++i) {
            // Timelock setup
            moduleManager.initiateAddModuleWithTimelock(whos[i]);
            vm.warp(block.timestamp + timelock);

            vm.expectEmit(true, true, true, true);
            emit ModuleAdded(whos[i]);

            moduleManager.executeAddModule(whos[i]);

            // Test timelock has been set to inactive (false)
            (timelockActive,) = moduleManager.moduleAddressToTimelock(whos[i]);

            assertTrue(moduleManager.isModule(whos[i]));
            assertFalse(timelockActive);
        }

        // Note that list is traversed.
        address[] memory modules = moduleManager.listModules();

        assertEq(modules.length, whos.length);
        for (uint i; i < whos.length; ++i) {
            assertEq(modules[i], whos[i]);
        }
    }

    function testExecuteAddModule_revertGivenTimelockNotExpired(
        address who,
        uint timePassed
    ) public {
        vm.assume(timePassed < timelock - 1);
        types.assumeValidModule(who);
        moduleManager.initiateAddModuleWithTimelock(who);

        (, uint timelockUntil) = moduleManager.moduleAddressToTimelock(who);

        // Set time passed such that timelock is still active
        vm.warp(block.timestamp + timePassed);
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManagerBase_v1
                    .ModuleManagerBase__ModuleUpdateTimelockStillActive
                    .selector,
                who,
                timelockUntil
            )
        );
        moduleManager.executeAddModule(who);
    }

    function testExecuteAddModule_revertGivenTimelockStillActive(address who)
        public
    {
        types.assumeValidModule(who);
        moduleManager.initiateAddModuleWithTimelock(who);

        // Cancel setting module
        moduleManager.cancelModuleUpdate(who);

        // Expect revert
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleUpdateAlreadyStarted
                .selector
        );

        moduleManager.executeAddModule(who);
    }

    function testInitiateAddModuleWithTimelock_FailsIfCallerNotAuthorized(
        address who
    ) public {
        types.assumeValidModule(who);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.initiateAddModuleWithTimelock(who);
    }

    function testExecuteAddModule_FailsIfCallerNotAuthorized(address who)
        public
    {
        types.assumeValidModule(who);
        moduleManager.initiateAddModuleWithTimelock(who);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.executeAddModule(who);
    }

    function testInitiateAddModuleWithTimelock_FailsIfAlreadyAdded(address who)
        public
    {
        types.assumeValidModule(who);

        moduleManager.initiateAddModuleWithTimelock(who);
        vm.warp(block.timestamp + timelock);
        moduleManager.executeAddModule(who);

        vm.expectRevert(
            IModuleManagerBase_v1.ModuleManagerBase__IsModule.selector
        );
        moduleManager.initiateAddModuleWithTimelock(who);
    }

    function testInitiateAddModuleWithTimelock_FailsForInvalidAddress()
        public
    {
        address[] memory invalids = types.createInvalidModules();

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IModuleManagerBase_v1
                    .ModuleManagerBase__InvalidModuleAddress
                    .selector
            );
            moduleManager.initiateAddModuleWithTimelock(invalids[i]);
        }
    }

    function testInitiateAddModuleWithTimelock_FailsIfLimitReached(
        address[] calldata whos
    ) public {
        vm.assume(whos.length > MAX_MODULES);
        types.assumeValidModules(whos[:MAX_MODULES]);

        for (uint i; i < MAX_MODULES; ++i) {
            moduleManager.initiateAddModuleWithTimelock(whos[i]);
            vm.warp(block.timestamp + timelock);
            vm.expectEmit(true, true, true, true);
            emit ModuleAdded(whos[i]);
            moduleManager.executeAddModule(whos[i]);

            assertTrue(moduleManager.isModule(whos[i]));
        }

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleAmountOverLimits
                .selector
        );
        moduleManager.initiateAddModuleWithTimelock(whos[MAX_MODULES]);
    }

    //----------------------------------
    // Tests: removeModules()

    function testExecuteRemoveModule_revertGivenTimelockNotExpired(
        address who,
        uint timePassed
    ) public {
        vm.assume(timePassed < timelock - 1);
        types.assumeValidModule(who);

        // Setup add module
        moduleManager.initiateAddModuleWithTimelock(who);
        vm.warp(block.timestamp + timelock);
        moduleManager.executeAddModule(who);

        // Initiate removing module
        moduleManager.initiateRemoveModuleWithTimelock(who);

        (, uint timelockUntil) = moduleManager.moduleAddressToTimelock(who);

        // Set time passed such that timelock is still active
        vm.warp(block.timestamp + timePassed);
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManagerBase_v1
                    .ModuleManagerBase__ModuleUpdateTimelockStillActive
                    .selector,
                who,
                timelockUntil
            )
        );
        moduleManager.executeRemoveModule(who);
    }

    function testExecuteRemoveModule_revertGivenTimelockStillActive(address who)
        public
    {
        types.assumeValidModule(who);
        // Setup add module
        moduleManager.initiateAddModuleWithTimelock(who);
        vm.warp(block.timestamp + timelock);
        moduleManager.executeAddModule(who);
        // Init setting module
        moduleManager.initiateRemoveModuleWithTimelock(who);
        // Cancel setting module
        moduleManager.cancelModuleUpdate(who);

        // Expect revert
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleUpdateAlreadyStarted
                .selector
        );

        moduleManager.executeRemoveModule(who);
    }

    function testRemoveModules(address[] memory whos) public {
        vm.assume(whos.length != 0);
        vm.assume(whos.length <= MAX_MODULES);
        types.assumeValidModules(whos);

        // The current module to remove.
        address module;

        // Add modules.
        for (uint i; i < whos.length; ++i) {
            moduleManager.initiateAddModuleWithTimelock(whos[i]);
            vm.warp(block.timestamp + timelock);
            moduleManager.executeAddModule(whos[i]);
        }

        // Remove modules from the front until list is empty.
        for (uint i; i < whos.length; ++i) {
            module = whos[whos.length - i - 1];

            moduleManager.initiateRemoveModuleWithTimelock(module);
            vm.warp(block.timestamp + timelock);

            vm.expectEmit(true, true, true, true);
            emit ModuleRemoved(module);

            moduleManager.executeRemoveModule(module);

            assertTrue(!moduleManager.isModule(module));
        }
        assertEq(moduleManager.listModules().length, 0);

        // Add modules again.
        for (uint i; i < whos.length; ++i) {
            moduleManager.initiateAddModuleWithTimelock(whos[i]);
            vm.warp(block.timestamp + timelock);
            moduleManager.executeAddModule(whos[i]);
        }

        // Remove modules from the back until list is empty.

        for (uint i; i < whos.length; ++i) {
            module = whos[i];

            moduleManager.initiateRemoveModuleWithTimelock(module);
            vm.warp(block.timestamp + timelock);

            vm.expectEmit(true, true, true, true);
            emit ModuleRemoved(module);

            moduleManager.executeRemoveModule(module);

            assertTrue(!moduleManager.isModule(module));
        }

        assertEq(moduleManager.listModules().length, 0);
    }

    function testInitiateRemoveModuleWithTimelock_FailsIfCallerNotAuthorized(
        address who
    ) public {
        types.assumeValidModule(who);

        moduleManager.initiateAddModuleWithTimelock(who);
        vm.warp(block.timestamp + timelock);
        moduleManager.executeAddModule(who);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.initiateRemoveModuleWithTimelock(who);
    }

    function testExecuteRemoveModule_FailsIfCallerNotAuthorized(address who)
        public
    {
        types.assumeValidModule(who);

        moduleManager.initiateAddModuleWithTimelock(who);
        vm.warp(block.timestamp + timelock);
        moduleManager.executeAddModule(who);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.initiateRemoveModuleWithTimelock(who);
    }

    function testInitiateRemoveModuleWithTimelock_FailsIfNotModule(address who)
        public
    {
        types.assumeValidModule(who);

        vm.expectRevert(
            IModuleManagerBase_v1.ModuleManagerBase__IsNotModule.selector
        );
        moduleManager.initiateRemoveModuleWithTimelock(who);
    }

    //----------------------------------
    // Tests: cancelModuleUpdate()
    /*
        Test cancelModuleUpdate() function
        ├── Given the caller of the function is not authorized
        │   └── When the function cancelModuleUpdate() gets called
        │       └── Then it should revert
        ├── Given no update has been initated for the module
        │   └── When the function cancelModuleUpdate() gets called
        │       └── Then it should revert
        └── Given caller is authorized & module update has been initiated
            └── When the function cancelModuleUpdate() gets called
                └── Then it should cancel the update
                    └── And it should emit an event
    */
    function testCancelModuleUpdate_failsGivenCallerNotAuthorized(address who)
        public
    {
        types.assumeValidModule(who);
        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.cancelModuleUpdate(who);
    }

    function testCancelModuleUpdate_failsGivenModuleUpdateNotInitated(
        address who
    ) public {
        types.assumeValidModule(who);
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleUpdateAlreadyStarted
                .selector
        );
        moduleManager.cancelModuleUpdate(who);
    }

    function testCancelModuleUpdate_worksGivenCallerAuthorizedAndUpdateInitiated(
        address[] memory whos
    ) public {
        vm.assume(whos.length <= MAX_MODULES);
        types.assumeValidModules(whos);
        bool timelockActive;

        for (uint i; i < whos.length; ++i) {
            // Test canceling both adding and removing modules
            if (i % 2 == 0) {
                // Test after initiating adding the module
                moduleManager.initiateAddModuleWithTimelock(whos[i]);
            } else {
                // Add module to pass isModule modifier check when initiating removal of module
                moduleManager.initiateAddModuleWithTimelock(whos[i]);
                vm.warp(block.timestamp + timelock);
                moduleManager.executeAddModule(whos[i]);

                // Test after initiating removing the module
                moduleManager.initiateRemoveModuleWithTimelock(whos[i]);
            }
            // validate timelock is active
            (timelockActive,) = moduleManager.moduleAddressToTimelock(whos[i]);
            assertTrue(timelockActive);

            // check for emit event
            vm.expectEmit(true, true, true, true, address(moduleManager));
            emit ModuleUpdateCanceled(whos[i]);
            moduleManager.cancelModuleUpdate(whos[i]);
            // validate timelock has been set to inactive
            (timelockActive,) = moduleManager.moduleAddressToTimelock(whos[i]);
            assertFalse(timelockActive);
        }
    }
}
