// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Internal Interfaces
import {
    IOrchestrator_v1,
    IAuthorizer_v1,
    IPaymentProcessor_v1
} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";

import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";

// Mocks
import {
    FundingManagerV1Mock,
    IFundingManager_v1
} from "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "test/utils/mocks/modules/PaymentProcessorV1Mock.sol";
import {GovernorV1Mock} from "test/utils/mocks/external/GovernorV1Mock.sol";
import {ModuleFactoryV1Mock} from
    "test/utils/mocks/factories/ModuleFactoryV1Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Helper
import {TypeSanityHelper} from "test/orchestrator/helper/TypeSanityHelper.sol";

contract OrchestratorV1Test is Test {
    // SuT
    Orchestrator_v1 orchestrator;

    // Helper
    TypeSanityHelper types;

    // Mocks
    FundingManagerV1Mock fundingManager;
    AuthorizerV1Mock authorizer;
    PaymentProcessorV1Mock paymentProcessor;
    GovernorV1Mock governor;
    ModuleFactoryV1Mock moduleFactory;
    ERC20Mock token;
    TransactionForwarder_v1 forwarder;

    event AuthorizerUpdated(address indexed _address);
    event FundingManagerUpdated(address indexed _address);
    event PaymentProcessorUpdated(address indexed _address);
    event OrchestratorInitialized(
        uint indexed orchestratorId_,
        address fundingManager,
        address authorizer,
        address paymentProcessor,
        address[] modules,
        address governor
    );

    function setUp() public {
        fundingManager = new FundingManagerV1Mock();
        authorizer = new AuthorizerV1Mock();
        paymentProcessor = new PaymentProcessorV1Mock();
        governor = new GovernorV1Mock();
        moduleFactory = new ModuleFactoryV1Mock();
        forwarder = new TransactionForwarder_v1("TransactionForwarder_v1");
        token = new ERC20Mock("TestToken", "TST");

        address impl = address(new Orchestrator_v1(address(forwarder)));
        orchestrator = Orchestrator_v1(Clones.clone(impl));

        types = new TypeSanityHelper(address(orchestrator));
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(uint orchestratorId, address[] memory modules) public {
        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }
            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(truncatedModules);

            vm.expectEmit(true, true, true, false);
            emit OrchestratorInitialized(
                orchestratorId,
                address(fundingManager),
                address(authorizer),
                address(paymentProcessor),
                truncatedModules,
                address(governor)
            );

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        } else {
            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            vm.expectEmit(true, true, true, false);
            emit OrchestratorInitialized(
                orchestratorId,
                address(fundingManager),
                address(authorizer),
                address(paymentProcessor),
                truncatedModules,
                address(governor)
            );

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                modules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        }

        // Check that orchestrator's storage correctly initialized.
        assertEq(orchestrator.orchestratorId(), orchestratorId);
        assertEq(address(orchestrator.authorizer()), address(authorizer));
        assertEq(
            address(orchestrator.paymentProcessor()), address(paymentProcessor)
        );

        assertEq(
            address(orchestrator.fundingManager()), address(fundingManager)
        );
        assertTrue(orchestrator.isTrustedForwarder(address(forwarder)));
    }

    function testReinitFails(uint orchestratorId, address[] memory modules)
        public
    {
        types.assumeValidOrchestratorId(orchestratorId);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);
            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );

            vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        } else {
            types.assumeValidModules(modules);
            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                modules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );

            vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                modules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        }
    }

    //--------------------------------------------------------------------------
    // Tests: Replacing the three base modules: authorizer, funding manager,
    //        payment processor

    function testInitiateAndExecuteSetAuthorizer(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new authorizer module
        AuthorizerV1Mock newAuthorizer = new AuthorizerV1Mock();
        vm.assume(newAuthorizer != authorizer);
        types.assumeElemNotInSet(modules, address(newAuthorizer));

        newAuthorizer.mockInit(abi.encode(address(0xA11CE)));

        orchestrator.initiateSetAuthorizerWithTimelock(newAuthorizer);
        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        // set the new authorizer module
        vm.expectEmit(true, true, true, true);
        emit AuthorizerUpdated(address(newAuthorizer));
        orchestrator.executeSetAuthorizer(newAuthorizer);

        assertTrue(orchestrator.authorizer() == newAuthorizer);

        // verify whether the init value is set and not the value from the old
        // authorizer, to check whether the replacement is successful
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertFalse(orchestrator.authorizer().hasRole(adminRole, address(this)));
        assertTrue(
            orchestrator.authorizer().hasRole(adminRole, address(0xA11CE))
        );
    }

    function testInitiateSetAuthorizerWithTimelock_FailsIfWrongModuleType(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new authorizer module
        address newAuthorizer = address(0x8888);
        vm.assume(newAuthorizer != address(authorizer));
        types.assumeElemNotInSet(modules, address(newAuthorizer));

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator__InvalidModuleType.selector,
                newAuthorizer
            )
        );
        orchestrator.initiateSetAuthorizerWithTimelock(
            IAuthorizer_v1(newAuthorizer)
        );
        assertTrue(orchestrator.authorizer() == authorizer);
    }

    function testInitiateAndExecuteSetFundingManager(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);
        FundingManagerV1Mock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        FundingManagerV1Mock newFundingManager = new FundingManagerV1Mock();
        vm.assume(newFundingManager != fundingManager);
        types.assumeElemNotInSet(modules, address(newFundingManager));

        orchestrator.initiateSetFundingManagerWithTimelock(newFundingManager);
        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        // set the new funding manager module
        vm.expectEmit(true, true, true, true);
        emit FundingManagerUpdated(address(newFundingManager));
        orchestrator.executeSetFundingManager(newFundingManager);
        assertTrue(orchestrator.fundingManager() == newFundingManager);
        assertTrue(
            address((orchestrator.fundingManager()).token()) == address(0)
        );
    }

    function testInitiateSetFundingManagerWithTimelock_FailsIfWrongModuleType(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);
        FundingManagerV1Mock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        address newFundingManager = address(0x8888);
        vm.assume(newFundingManager != address(fundingManager));
        types.assumeElemNotInSet(modules, newFundingManager);

        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator__InvalidModuleType.selector,
                newFundingManager
            )
        );
        orchestrator.initiateSetFundingManagerWithTimelock(
            IFundingManager_v1(newFundingManager)
        );
        assertTrue(orchestrator.fundingManager() == fundingManager);
    }

    function testInitiateAndExecuteSetPaymentProcessor(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new payment processor module
        PaymentProcessorV1Mock newPaymentProcessor =
            new PaymentProcessorV1Mock();
        vm.assume(newPaymentProcessor != paymentProcessor);
        types.assumeElemNotInSet(modules, address(newPaymentProcessor));

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            newPaymentProcessor
        );
        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        // set the new payment processor module
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessorUpdated(address(newPaymentProcessor));
        orchestrator.executeSetPaymentProcessor(newPaymentProcessor);
        assertTrue(orchestrator.paymentProcessor() == newPaymentProcessor);
    }

    function testInitiateSetPaymentProcessorWithTimelock_FailsIfWrongModuleType(
        uint orchestratorId,
        address[] memory modules
    ) public {
        // limit to 100, otherwise we could run into the max module limit
        modules = cutArray(100, modules);

        types.assumeValidOrchestratorId(orchestratorId);
        types.assumeValidModules(modules);

        // Make sure mock addresses are not in set of modules.
        assumeMockAreNotInSet(modules);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);

        // Create new payment processor module
        address newPaymentProcessor = address(0x8888);
        vm.assume(newPaymentProcessor != address(paymentProcessor));
        types.assumeElemNotInSet(modules, newPaymentProcessor);

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator__InvalidModuleType.selector,
                newPaymentProcessor
            )
        );
        orchestrator.initiateSetPaymentProcessorWithTimelock(
            IPaymentProcessor_v1(newPaymentProcessor)
        );

        assertTrue(orchestrator.paymentProcessor() == paymentProcessor);
    }

    /*  Test function initiateRemoveModuleWithTimelock
        ├── Given the module address to be removed is the current authorizer
        │   └── When the function initiateRemoveModuleWithTimelock() gets called
        │       └── Then the function should revert
        ├── Given the module address to be removed is the current funding manager
        │   └── When the function initiateRemoveModuleWithTimelock() gets called
        │       └── Then the function should revert
        └── Given the module address to be removed is the current payment processor
            └── When the function initiateRemoveModuleWithTimelock() gets called
                └── Then the function should revert
    */

    function testInitiateRemoveModuleWithTimelock_failsGivenModuleAddressIsCurrentAuthorizer(
    ) public {
        orchestrator.init(
            1,
            address(moduleFactory),
            new address[](0),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);
        address currentAuthorizer = address(orchestrator.authorizer());

        vm.expectRevert(
            IOrchestrator_v1.Orchestrator__InvalidRemovalOfAuthorizer.selector
        );
        orchestrator.initiateRemoveModuleWithTimelock(currentAuthorizer);
    }

    function testInitiateRemoveModuleWithTimelock_failsGivenModuleAddressIsCurrentFundingManager(
    ) public {
        orchestrator.init(
            1,
            address(moduleFactory),
            new address[](0),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );
        address currentFundingManager = address(orchestrator.fundingManager());

        vm.expectRevert(
            IOrchestrator_v1
                .Orchestrator__InvalidRemovalOfFundingManager
                .selector
        );
        orchestrator.initiateRemoveModuleWithTimelock(currentFundingManager);
    }

    function testInitiateRemoveModuleWithTimelock_failsGivenModuleAddressIsCurrentPaymentProcessor(
    ) public {
        orchestrator.init(
            1,
            address(moduleFactory),
            new address[](0),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );
        address currentPaymentProcessor =
            address(orchestrator.paymentProcessor());

        vm.expectRevert(
            IOrchestrator_v1
                .Orchestrator__InvalidRemovalOfPaymentProcessor
                .selector
        );
        orchestrator.initiateRemoveModuleWithTimelock(currentPaymentProcessor);
    }
    /*  Test function executeRemoveModule
        ├── Given the module address to be removed is the current authorizer
        │   └── When the function executeRemoveModule() gets called
        │       └── Then the function should revert
        ├── Given the module address to be removed is the current funding manager
        │   └── When the function executeRemoveModule() gets called
        │       └── Then the function should revert
        └── Given the module address to be removed is the current payment processor
            └── When the function executeRemoveModule() gets called
                └── Then the function should revert
    */

    function testExecuteRemoveModule_failsGivenModuleAddressIsCurrentAuthorizer(
    ) public {
        orchestrator.init(
            1,
            new address[](0),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        authorizer.setIsAuthorized(address(this), true);
        address currentAuthorizer = address(orchestrator.authorizer());

        vm.expectRevert(
            IOrchestrator_v1.Orchestrator__InvalidRemovalOfAuthorizer.selector
        );
        orchestrator.executeRemoveModule(currentAuthorizer);
    }

    function testExecuteRemoveModule_failsGivenModuleAddressIsCurrentFundingManager(
    ) public {
        orchestrator.init(
            1,
            new address[](0),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );
        address currentFundingManager = address(orchestrator.fundingManager());

        vm.expectRevert(
            IOrchestrator_v1
                .Orchestrator__InvalidRemovalOfFundingManager
                .selector
        );
        orchestrator.executeRemoveModule(currentFundingManager);
    }

    function testExecuteRemoveModule_failsGivenModuleAddressIsCurrentPaymentProcessor(
    ) public {
        orchestrator.init(
            1,
            new address[](0),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );
        address currentPaymentProcessor =
            address(orchestrator.paymentProcessor());

        vm.expectRevert(
            IOrchestrator_v1
                .Orchestrator__InvalidRemovalOfPaymentProcessor
                .selector
        );
        orchestrator.executeRemoveModule(currentPaymentProcessor);
    }

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTx(uint orchestratorId, address[] memory modules)
        public
    {
        types.assumeValidOrchestratorId(orchestratorId);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of truncatedModules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        } else {
            types.assumeValidModules(modules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                modules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        }
        authorizer.setIsAuthorized(address(this), true);

        bytes memory returnData = orchestrator.executeTx(
            address(this), abi.encodeWithSignature("ok()")
        );
        assertTrue(abi.decode(returnData, (bool)));
    }

    function testExecuteTxFailsIfCallFails(
        uint orchestratorId,
        address[] memory modules
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of truncatedModules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        } else {
            types.assumeValidModules(modules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                modules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        }

        authorizer.setIsAuthorized(address(this), true);

        vm.expectRevert(IOrchestrator_v1.Orchestrator__ExecuteTxFailed.selector);
        orchestrator.executeTx(
            address(this), abi.encodeWithSignature("fails()")
        );
    }

    function testExecuteTxFailsIfCallerNotAuthorized(
        uint orchestratorId,
        address[] memory modules
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);

        address[] memory truncatedModules = new address[](125);
        if (modules.length > 125) {
            for (uint i; i < 125; i++) {
                truncatedModules[i] = modules[i];
            }

            types.assumeValidModules(truncatedModules);

            // Make sure mock addresses are not in set of truncatedModules.
            assumeMockAreNotInSet(truncatedModules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                truncatedModules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        } else {
            types.assumeValidModules(modules);

            // Make sure mock addresses are not in set of modules.
            assumeMockAreNotInSet(modules);

            // Initialize orchestrator.
            orchestrator.init(
                orchestratorId,
                address(moduleFactory),
                modules,
                fundingManager,
                authorizer,
                paymentProcessor,
                governor
            );
        }

        authorizer.setIsAuthorized(address(this), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v1.Orchestrator__CallerNotAuthorized.selector,
                authorizer.getAdminRole(),
                address(this)
            )
        );
        orchestrator.executeTx(address(this), abi.encodeWithSignature("ok()"));
    }

    function ok() public pure returns (bool) {
        return true;
    }

    function fails() public pure {
        revert("failed");
    }

    //--------------------------------------------------------------------------
    // Tests: Other

    function testVersion() public {
        assertEq(orchestrator.version(), "1");
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function assumeMockAreNotInSet(address[] memory modules) private view {
        types.assumeElemNotInSet(modules, address(fundingManager));
        types.assumeElemNotInSet(modules, address(authorizer));
        types.assumeElemNotInSet(modules, address(paymentProcessor));
        types.assumeElemNotInSet(modules, address(token));
    }

    function cutArray(uint size, address[] memory addrs)
        internal
        pure
        returns (address[] memory)
    {
        uint length = addrs.length;
        vm.assume(length > 0); //Array has to be at least 1

        if (length <= size) {
            return addrs;
        }

        address[] memory cutArry = new address[](size);
        for (uint i; i < size - 1;) {
            cutArry[i] = addrs[i];
            unchecked {
                ++i;
            }
        }
        return cutArry;
    }
}
