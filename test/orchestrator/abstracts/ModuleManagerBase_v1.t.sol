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
import {ModuleV1Mock} from "test/utils/mocks/modules/base/ModuleV1Mock.sol";

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

    function testInit(uint moduleAmount) public {
        address[] memory modules = createModules(moduleAmount, MAX_MODULES);

        moduleManager = new ModuleManagerBaseV1Mock(address(0));
        types = new TypeSanityHelper(address(moduleManager));

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

        address module = address(new ModuleV1Mock());

        address[] memory modules = new address[](2);
        modules[0] = module;
        modules[1] = module;

        vm.expectRevert(
            IModuleManagerBase_v1.ModuleManagerBase__IsModule.selector
        );
        moduleManager.init(modules);
    }

    function testInitFailsForTooManyModules(uint moduleAmount) public {
        vm.assume(moduleAmount > MAX_MODULES);
        address[] memory modules = createModules(moduleAmount, 1000);

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
        address module = address(new ModuleV1Mock());

        moduleManager.call_initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.call_executeAddModule(module);

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
        address module = address(new ModuleV1Mock());
        moduleManager.call_initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.call_executeAddModule(module);

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

    function testAddModule(uint moduleAmount) public {
        address[] memory modules = createModules(moduleAmount, MAX_MODULES);
        bool timelockActive;

        for (uint i; i < modules.length; ++i) {
            // Timelock setup
            moduleManager.call_initiateAddModuleWithTimelock(modules[i]);
            vm.warp(block.timestamp + timelock);

            vm.expectEmit(true, true, true, true);
            emit ModuleAdded(modules[i]);

            moduleManager.call_executeAddModule(modules[i]);

            // Test timelock has been set to inactive (false)
            (timelockActive,) =
                moduleManager.moduleAddressToTimelock(modules[i]);

            assertTrue(moduleManager.isModule(modules[i]));
            assertFalse(timelockActive);
        }

        // Note that list is traversed.
        address[] memory listedModules = moduleManager.listModules();

        assertEq(listedModules.length, modules.length);
        for (uint i; i < modules.length; ++i) {
            assertEq(modules[i], listedModules[i]);
        }
    }

    function testExecuteAddModule_revertGivenTimelockNotExpired(uint timePassed)
        public
    {
        vm.assume(timePassed < timelock - 1);

        address module = address(new ModuleV1Mock());
        moduleManager.call_initiateAddModuleWithTimelock(module);

        (, uint timelockUntil) = moduleManager.moduleAddressToTimelock(module);

        // Set time passed such that timelock is still active
        vm.warp(block.timestamp + timePassed);
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManagerBase_v1
                    .ModuleManagerBase__ModuleUpdateTimelockStillActive
                    .selector,
                module,
                timelockUntil
            )
        );
        moduleManager.call_executeAddModule(module);
    }

    function testExecuteAddModule_revertGivenTimelockStillActive() public {
        address module = address(new ModuleV1Mock());
        moduleManager.call_initiateAddModuleWithTimelock(module);

        // Cancel setting module
        moduleManager.call_cancelModuleUpdate(module);

        // Expect revert
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleUpdateAlreadyStarted
                .selector
        );

        moduleManager.call_executeAddModule(module);
    }

    function testInitiateAddModuleWithTimelock_FailsIfCallerNotAuthorized()
        public
    {
        address module = address(new ModuleV1Mock());

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.call_initiateAddModuleWithTimelock(module);
    }

    function testExecuteAddModule_FailsIfCallerNotAuthorized() public {
        address module = address(new ModuleV1Mock());
        moduleManager.call_initiateAddModuleWithTimelock(module);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.call_executeAddModule(module);
    }

    function testInitiateAddModuleWithTimelock_FailsIfAlreadyAdded() public {
        address module = address(new ModuleV1Mock());

        moduleManager.call_initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.call_executeAddModule(module);

        vm.expectRevert(
            IModuleManagerBase_v1.ModuleManagerBase__IsModule.selector
        );
        moduleManager.call_initiateAddModuleWithTimelock(module);
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
            moduleManager.call_initiateAddModuleWithTimelock(invalids[i]);
        }
    }

    function testInitiateAddModuleWithTimelock_FailsIfLimitReached(
        uint moduleAmount
    ) public {
        moduleAmount = bound(moduleAmount, MAX_MODULES + 1, 1000);
        address[] memory modules = createModules(moduleAmount, 1000);

        for (uint i; i < MAX_MODULES; ++i) {
            moduleManager.call_initiateAddModuleWithTimelock(modules[i]);
            vm.warp(block.timestamp + timelock);
            vm.expectEmit(true, true, true, true);
            emit ModuleAdded(modules[i]);
            moduleManager.call_executeAddModule(modules[i]);

            assertTrue(moduleManager.isModule(modules[i]));
        }

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleAmountOverLimits
                .selector
        );
        moduleManager.call_initiateAddModuleWithTimelock(modules[MAX_MODULES]);
    }

    //----------------------------------
    // Tests: removeModules()

    function testExecuteRemoveModule_revertGivenTimelockNotExpired(
        uint timePassed
    ) public {
        vm.assume(timePassed < timelock - 1);

        address module = address(new ModuleV1Mock());

        // Setup add module
        moduleManager.call_initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.call_executeAddModule(module);

        // Initiate removing module
        moduleManager.call_initiateRemoveModuleWithTimelock(module);

        (, uint timelockUntil) = moduleManager.moduleAddressToTimelock(module);

        // Set time passed such that timelock is still active
        vm.warp(block.timestamp + timePassed);
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManagerBase_v1
                    .ModuleManagerBase__ModuleUpdateTimelockStillActive
                    .selector,
                module,
                timelockUntil
            )
        );
        moduleManager.call_executeRemoveModule(module);
    }

    function testExecuteRemoveModule_revertGivenTimelockStillActive() public {
        address module = address(new ModuleV1Mock());
        // Setup add module
        moduleManager.call_initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.call_executeAddModule(module);
        // Init setting module
        moduleManager.call_initiateRemoveModuleWithTimelock(module);
        // Cancel setting module
        moduleManager.call_cancelModuleUpdate(module);

        // Expect revert
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleUpdateAlreadyStarted
                .selector
        );

        moduleManager.call_executeRemoveModule(module);
    }

    function testRemoveModules(uint moduleAmount) public {
        moduleAmount = bound(moduleAmount, 1, MAX_MODULES);
        address[] memory modules = createModules(moduleAmount, MAX_MODULES);

        // The current module to remove.
        address module;

        // Add modules.
        for (uint i; i < modules.length; ++i) {
            moduleManager.call_initiateAddModuleWithTimelock(modules[i]);
            vm.warp(block.timestamp + timelock);
            moduleManager.call_executeAddModule(modules[i]);
        }

        // Remove modules from the front until list is empty.
        for (uint i; i < modules.length; ++i) {
            module = modules[modules.length - i - 1];

            moduleManager.call_initiateRemoveModuleWithTimelock(module);
            vm.warp(block.timestamp + timelock);

            vm.expectEmit(true, true, true, true);
            emit ModuleRemoved(module);

            moduleManager.call_executeRemoveModule(module);

            assertTrue(!moduleManager.isModule(module));
        }
        assertEq(moduleManager.listModules().length, 0);

        // Add modules again.
        for (uint i; i < modules.length; ++i) {
            moduleManager.call_initiateAddModuleWithTimelock(modules[i]);
            vm.warp(block.timestamp + timelock);
            moduleManager.call_executeAddModule(modules[i]);
        }

        // Remove modules from the back until list is empty.

        for (uint i; i < modules.length; ++i) {
            module = modules[i];

            moduleManager.call_initiateRemoveModuleWithTimelock(module);
            vm.warp(block.timestamp + timelock);

            vm.expectEmit(true, true, true, true);
            emit ModuleRemoved(module);

            moduleManager.call_executeRemoveModule(module);

            assertTrue(!moduleManager.isModule(module));
        }

        assertEq(moduleManager.listModules().length, 0);
    }

    function testInitiateRemoveModuleWithTimelock_FailsIfCallerNotAuthorized()
        public
    {
        address module = address(new ModuleV1Mock());

        moduleManager.call_initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.call_executeAddModule(module);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.call_initiateRemoveModuleWithTimelock(module);
    }

    function testExecuteRemoveModule_FailsIfCallerNotAuthorized() public {
        address module = address(new ModuleV1Mock());

        moduleManager.call_initiateAddModuleWithTimelock(module);
        vm.warp(block.timestamp + timelock);
        moduleManager.call_executeAddModule(module);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.call_initiateRemoveModuleWithTimelock(module);
    }

    function testInitiateRemoveModuleWithTimelock_FailsIfNotModule() public {
        address module = address(new ModuleV1Mock());

        vm.expectRevert(
            IModuleManagerBase_v1.ModuleManagerBase__IsNotModule.selector
        );
        moduleManager.call_initiateRemoveModuleWithTimelock(module);
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
    function testCancelModuleUpdate_failsGivenCallerNotAuthorized() public {
        address module = address(new ModuleV1Mock());
        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__CallerNotAuthorized
                .selector
        );
        moduleManager.call_cancelModuleUpdate(module);
    }

    function testCancelModuleUpdate_failsGivenModuleUpdateNotInitated()
        public
    {
        address module = address(new ModuleV1Mock());
        vm.expectRevert(
            IModuleManagerBase_v1
                .ModuleManagerBase__ModuleUpdateAlreadyStarted
                .selector
        );
        moduleManager.call_cancelModuleUpdate(module);
    }

    function testCancelModuleUpdate_worksGivenCallerAuthorizedAndUpdateInitiated(
        uint moduleAmount
    ) public {
        address[] memory modules = createModules(moduleAmount, MAX_MODULES);
        bool timelockActive;

        for (uint i; i < modules.length; ++i) {
            // Test canceling both adding and removing modules
            if (i % 2 == 0) {
                // Test after initiating adding the module
                moduleManager.call_initiateAddModuleWithTimelock(modules[i]);
            } else {
                // Add module to pass isModule modifier check when initiating removal of module
                moduleManager.call_initiateAddModuleWithTimelock(modules[i]);
                vm.warp(block.timestamp + timelock);
                moduleManager.call_executeAddModule(modules[i]);

                // Test after initiating removing the module
                moduleManager.call_initiateRemoveModuleWithTimelock(modules[i]);
            }
            // validate timelock is active
            (timelockActive,) =
                moduleManager.moduleAddressToTimelock(modules[i]);
            assertTrue(timelockActive);

            // check for emit event
            vm.expectEmit(true, true, true, true, address(moduleManager));
            emit ModuleUpdateCanceled(modules[i]);
            moduleManager.call_cancelModuleUpdate(modules[i]);
            // validate timelock has been set to inactive
            (timelockActive,) =
                moduleManager.moduleAddressToTimelock(modules[i]);
            assertFalse(timelockActive);
        }
    }

    function createModules(uint amount, uint maxAmount)
        internal
        returns (address[] memory modules)
    {
        if (amount > maxAmount) {
            amount = maxAmount;
        }

        modules = new address[](amount);
        for (uint i = 0; i < amount; i++) {
            modules[i] = address(new ModuleV1Mock());
        }
    }
}
