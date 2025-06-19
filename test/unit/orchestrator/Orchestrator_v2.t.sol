// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Orchestrator_v2_Exposed} from
    "@mocks/orchestrator/Orchestrator_v2_Exposed.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModule_v2} from "src/modules/base/IModule_v2.sol";

// Internal Interfaces
import {
    IOrchestrator_v2,
    IAuthorizer_v2,
    IPaymentProcessor_v3
} from "src/orchestrator/interfaces/IOrchestrator_v2.sol";

import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";

// Mocks
import {
    FundingManagerV1Mock,
    IFundingManager_v1
} from "@mocks/modules/fundingManager/FundingManagerV1Mock.sol";
import {
    Authorizer_v1_Mock,
    IAuthorizer_v1
} from "@mocks/modules/authorizer/Authorizer_v1_Mock.sol";
import {
    Authorizer_v2_Mock,
    IAuthorizer_v2
} from "@mocks/modules/authorizer/Authorizer_v2_Mock.sol";
import {
    PaymentProcessor_v1_Mock,
    IPaymentProcessor_v1
} from "@mocks/modules/paymentProcessor/PaymentProcessor_v1_Mock.sol";
import {
    PaymentProcessor_v2_Mock,
    IPaymentProcessor_v2
} from "@mocks/modules/paymentProcessor/PaymentProcessor_v2_Mock.sol";
import {
    PaymentProcessor_v3_Mock,
    IPaymentProcessor_v3
} from "@mocks/modules/paymentProcessor/PaymentProcessor_v3_Mock.sol";
import {GovernorV1Mock} from "@mocks/external/governance/GovernorV1Mock.sol";
import {ModuleFactoryV1Mock} from "@mocks/factories/ModuleFactoryV1Mock.sol";
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

import {Module_v2_Mock} from "@mocks/modules/base/Module_v2_Mock.sol";
// Errors
import {OZErrors} from "@testUtilities/OZErrors.sol";

// Helper
import {TypeSanityHelper} from "@testUtilities/TypeSanityHelper.sol";
import {ERC165InterfaceMock} from "@testUtilities/ERC165InterfaceMock.sol";

contract OrchestratorV1Test is Test {
    // SuT
    Orchestrator_v2_Exposed orchestrator;

    // Helper
    TypeSanityHelper types;

    // Mocks
    FundingManagerV1Mock fundingManager;
    Authorizer_v2_Mock authorizer;
    PaymentProcessor_v3_Mock paymentProcessor;
    GovernorV1Mock governor;
    ModuleFactoryV1Mock moduleFactory;
    ERC20Mock token;
    TransactionForwarder_v1 forwarder;

    function setUp() public {
        fundingManager = new FundingManagerV1Mock();
        authorizer = new Authorizer_v2_Mock();
        paymentProcessor = new PaymentProcessor_v3_Mock();
        governor = new GovernorV1Mock();
        moduleFactory = new ModuleFactoryV1Mock();
        forwarder = new TransactionForwarder_v1();
        token = new ERC20Mock("TestToken", "TST", 18);

        address impl = address(new Orchestrator_v2_Exposed(address(forwarder)));
        orchestrator = Orchestrator_v2_Exposed(Clones.clone(impl));

        types = new TypeSanityHelper(address(orchestrator));

        // Actually link the Authorizer to the Orchestrator
        orchestrator.setup_authorizer(address(authorizer));

        // Set the default admin to this contract
        authorizer.setDefaultAdmin(address(this));

        // Every caller has permission for every permissioned function
        authorizer.setAllAuthorized(true);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(uint orchestratorId, uint moduleAmount) public {
        types.assumeValidOrchestratorId(orchestratorId);

        address[] memory modules = createModules(moduleAmount);

        address wrongModule = address(new Module_v2_Mock());

        // We expect reverts when trying to set the wrong module as any of the privileged modules
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                wrongModule
            )
        );
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            IFundingManager_v1(wrongModule),
            authorizer,
            paymentProcessor,
            governor
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                wrongModule
            )
        );
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            IAuthorizer_v2(wrongModule),
            paymentProcessor,
            governor
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                wrongModule
            )
        );
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            IPaymentProcessor_v3(wrongModule),
            governor
        );

        // Now we test correct initialization
        vm.expectEmit(true, true, true, false);
        emit IOrchestrator_v2.OrchestratorInitialized(
            orchestratorId,
            address(fundingManager),
            address(authorizer),
            address(paymentProcessor),
            modules,
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

    function testReinitFails(uint orchestratorId, uint moduleAmount) public {
        address[] memory modules = createModules(moduleAmount);

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

    //--------------------------------------------------------------------------
    // Tests: Modifiers

    /*
    Test: permissioned
    ├── Given: modifierPermissionedCheck is executed via call with a valid selector, but random data
    ├── And: The call sender is randomised
    └── And: The Caller is permissioned to call the function
        └── When: The function modifierPermissionedCheck is called
            └── Then: the function should not revert, because the sender and only the function selector were correctly passed
    */
    function testPermissioned_modifier(address caller_, bytes memory data_)
        public
    {
        // Assume that the calldata is at least 4 bytes long
        vm.assume(data_.length >= 4);

        bytes4 targetSelector =
            Orchestrator_v2_Exposed.modifierPermissionedCheck.selector;

        // Proof
        authorizer.setHasPermission(
            caller_, address(orchestrator), targetSelector, true
        );

        // Replace the msg.data function selector with the correct one
        for (uint i = 0; i < 4; i++) {
            data_[i] = targetSelector[i];
        }

        // Expect no revert
        vm.prank(caller_);
        address(orchestrator).call(data_);
    }

    //--------------------------------------------------------------------------
    // Tests: Replacing the three base modules: authorizer, funding manager,
    //        payment processor

    /* 
    Test: initiateSetAuthorizerWithTimelock Modifier Checks
    └── Given: caller is not permissioned
        └── When: initiateSetAuthorizerWithTimelock is called
            └── Then: it should revert (modifier in position check)
    */
    function testInitiateSetAuthorizerWithTimelock_ModifierInPositionChecks()
        public
    {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);

        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);

        vm.prank(address(0xB0B));
        orchestrator.initiateSetAuthorizerWithTimelock(address(0));
    }

    /*
    Test: executeSetAuthorizer Modifier Checks
    └── Given: caller is not permissioned
        └── When: executeSetAuthorizer is called
            └── Then: it should revert (modifier in position check)
    */
    function testExecuteSetAuthorizer_ModifierInPositionChecks() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);
        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);
        vm.prank(address(0xB0B));
        orchestrator.executeSetAuthorizer(address(0));
    }

    /*
    Test: cancelAuthorizerUpdate Modifier Checks
    └── Given: caller is not permissioned
        └── When: cancelAuthorizerUpdate is called
            └── Then: it should revert (modifier in position check)
    */
    function testCancelAuthorizerUpdate_ModifierInPositionChecks() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);
        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);
        vm.prank(address(0xB0B));
        orchestrator.cancelAuthorizerUpdate(address(0));
    }

    function testInitiateSetAuthorizerWithTimelock_SupportsIAuthorizer_v1()
        public
    {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new authorizer module
        Authorizer_v1_Mock newAuthorizer_v1 = new Authorizer_v1_Mock();

        orchestrator.initiateSetAuthorizerWithTimelock(
            address(newAuthorizer_v1)
        );
    }

    function testInitiateSetAuthorizerWithTimelock_SupportsIAuthorizer_v2()
        public
    {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new authorizer module
        Authorizer_v2_Mock newAuthorizer_v2 = new Authorizer_v2_Mock();

        orchestrator.initiateSetAuthorizerWithTimelock(
            address(newAuthorizer_v2)
        );
    }

    function testExecuteSetAuthorizerWithTimelock_SupportsIAuthorizer_v1()
        public
    {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new authorizer module
        Authorizer_v1_Mock newAuthorizer_v1 = new Authorizer_v1_Mock();

        orchestrator.initiateSetAuthorizerWithTimelock(
            address(newAuthorizer_v1)
        );

        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        orchestrator.executeSetAuthorizer(address(newAuthorizer_v1));
    }

    function testExecuteSetAuthorizerWithTimelock_SupportsIAuthorizer_v2()
        public
    {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new authorizer module
        Authorizer_v2_Mock newAuthorizer_v2 = new Authorizer_v2_Mock();

        orchestrator.initiateSetAuthorizerWithTimelock(
            address(newAuthorizer_v2)
        );

        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        orchestrator.executeSetAuthorizer(address(newAuthorizer_v2));
    }

    function testInitiateAndExecuteSetAuthorizer(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new authorizer module
        Authorizer_v2_Mock newAuthorizer = new Authorizer_v2_Mock();

        newAuthorizer.mockInit(abi.encode(address(0xA11CE)));

        orchestrator.initiateSetAuthorizerWithTimelock(address(newAuthorizer));
        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        // set the new authorizer module
        vm.expectEmit(true, true, true, true);
        emit IOrchestrator_v2.AuthorizerUpdated(address(newAuthorizer));
        orchestrator.executeSetAuthorizer(address(newAuthorizer));

        assertTrue(orchestrator.authorizer() == newAuthorizer);

        // verify whether the init value is set and not the value from the old
        // authorizer, to check whether the replacement is successful
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertFalse(orchestrator.authorizer().hasRole(adminRole, address(this)));
        assertTrue(
            orchestrator.authorizer().hasRole(adminRole, address(0xA11CE))
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testExecuteSetAuthorizer_FailsIfWrongModuleType(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new authorizer module
        address newAuthorizer = address(0x8888);

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                newAuthorizer
            )
        );
        orchestrator.executeSetAuthorizer(newAuthorizer);
        assertTrue(orchestrator.authorizer() == authorizer);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testInitiateSetAuthorizerWithTimelock_FailsIfWrongModuleType(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new authorizer module
        address newAuthorizer = address(0x8888);

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                newAuthorizer
            )
        );
        orchestrator.initiateSetAuthorizerWithTimelock(newAuthorizer);
        assertTrue(orchestrator.authorizer() == authorizer);
    }

    /*
    Test: initiateSetFundingManagerWithTimelock Modifier Checks
    └── Given: caller is not permissioned
        └── When: initiateSetFundingManagerWithTimelock is called
            └── Then: it should revert (modifier in position check)
    */
    function testInitiateSetFundingManagerWithTimelock_ModifierInPositionChecks(
    ) public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);

        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);

        vm.prank(address(0xB0B));
        orchestrator.initiateSetFundingManagerWithTimelock(address(0));
    }

    /*
    Test: executeSetFundingManager Modifier Checks
    └── Given: caller is not permissioned
        └── When: executeSetFundingManager is called
            └── Then: it should revert (modifier in position check)
    */
    function testExecuteSetFundingManager_ModifierInPositionChecks() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);
        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);
        vm.prank(address(0xB0B));
        orchestrator.executeSetFundingManager(address(0));
    }

    /*
    Test: cancelFundingManagerUpdate Modifier Checks
    └── Given: caller is not permissioned
        └── When: cancelFundingManagerUpdate is called
            └── Then: it should revert (modifier in position check)
    */
    function testCancelFundingManagerUpdate_ModifierInPositionChecks() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);
        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);
        vm.prank(address(0xB0B));
        orchestrator.cancelFundingManagerUpdate(address(0));
    }

    function testInitiateSetFundingmanagerWithTimelock_SupportsIFundingManager_v1(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new funding manager module
        FundingManagerV1Mock newFundingManager_v1 = new FundingManagerV1Mock();

        orchestrator.initiateSetFundingManagerWithTimelock(
            address(newFundingManager_v1)
        );
    }

    function testExecuteSetFundingmanagerWithTimelock_SupportsIFundingManager_v1(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new funding manager module
        FundingManagerV1Mock newFundingManager_v1 = new FundingManagerV1Mock();

        orchestrator.initiateSetFundingManagerWithTimelock(
            address(newFundingManager_v1)
        );

        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        orchestrator.executeSetFundingManager(address(newFundingManager_v1));
    }

    function testInitiateAndExecuteSetFundingManager(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);

        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        FundingManagerV1Mock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        FundingManagerV1Mock newFundingManager = new FundingManagerV1Mock();
        newFundingManager.setToken(IERC20(address(0xA11CE)));

        orchestrator.initiateSetFundingManagerWithTimelock(
            address(newFundingManager)
        );
        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        // set the new funding manager module
        vm.expectEmit(true, true, true, true);
        emit IOrchestrator_v2.FundingManagerUpdated(address(newFundingManager));
        orchestrator.executeSetFundingManager(address(newFundingManager));
        assertTrue(orchestrator.fundingManager() == newFundingManager);
        assertTrue(
            address((orchestrator.fundingManager()).token()) == address(0xA11CE)
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testInitiateSetFundingManagerWithTimelock_FailsIfWrongModuleType(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        FundingManagerV1Mock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        address newFundingManager = address(0x8888);

        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                newFundingManager
            )
        );
        orchestrator.initiateSetFundingManagerWithTimelock(newFundingManager);
        assertTrue(orchestrator.fundingManager() == fundingManager);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testExecuteSetFundingManager_FailsIfWrongModuleType(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        FundingManagerV1Mock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        address newFundingManager = address(0x8888);

        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                newFundingManager
            )
        );
        orchestrator.executeSetFundingManager(newFundingManager);
        assertTrue(orchestrator.fundingManager() == fundingManager);
    }

    function testInitiateAndExecuteSetFundingManager_failsIfMismatchedTokens(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        FundingManagerV1Mock(address(orchestrator.fundingManager())).setToken(
            IERC20(address(0xA11CE))
        );

        // Create new funding manager module
        FundingManagerV1Mock newFundingManager = new FundingManagerV1Mock();
        newFundingManager.setToken(IERC20(address(0xB0B)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2
                    .Orchestrator__MismatchedTokenForFundingManager
                    .selector,
                orchestrator.fundingManager().token(),
                newFundingManager.token()
            )
        );
        orchestrator.initiateSetFundingManagerWithTimelock(
            address(newFundingManager)
        );
    }

    /*
    Test: initiateSetPaymentProcessorWithTimelock Modifier Checks
    └── Given: caller is not permissioned
        └── When: initiateSetPaymentProcessorWithTimelock is called
            └── Then: it should revert (modifier in position check)
    */
    function testInitiateSetPaymentProcessorWithTimelock_ModifierInPositionChecks(
    ) public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);

        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);

        vm.prank(address(0xB0B));
        orchestrator.initiateSetPaymentProcessorWithTimelock(address(0));
    }

    /*
    Test: executeSetPaymentProcessor Modifier Checks
    └── Given: caller is not permissioned
        └── When: executeSetPaymentProcessor is called
            └── Then: it should revert (modifier in position check)
    */
    function testExecuteSetPaymentProcessor_ModifierInPositionChecks() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);
        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);
        vm.prank(address(0xB0B));
        orchestrator.executeSetPaymentProcessor(address(0));
    }

    /*
    Test: cancelPaymentProcessorUpdate Modifier Checks
    └── Given: caller is not permissioned
        └── When: cancelPaymentProcessorUpdate is called
            └── Then: it should revert (modifier in position check)
    */
    function testCancelPaymentProcessorUpdate_ModifierInPositionChecks()
        public
    {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        authorizer.setAllAuthorized(false);
        vm.expectRevert(IOrchestrator_v2.Orchestrator__NotPermissioned.selector);
        vm.prank(address(0xB0B));
        orchestrator.cancelPaymentProcessorUpdate(address(0));
    }

    function testInitiateSetpaymentProcessorWithTimelock_SupportsIPaymentProcessor_v1(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor_v1 = address(new PaymentProcessor_v1_Mock());

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            address(newPaymentProcessor_v1)
        );
    }

    function testInitiateSetpaymentProcessorWithTimelock_SupportsIPaymentProcessor_v2(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor_v2 = address(new PaymentProcessor_v2_Mock());

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            address(newPaymentProcessor_v2)
        );
    }

    function testInitiateSetpaymentProcessorWithTimelock_SupportsIPaymentProcessor_v3(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor_v3 = address(new PaymentProcessor_v3_Mock());

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            address(newPaymentProcessor_v3)
        );
    }

    function testExecuteSetpaymentProcessorWithTimelock_SupportsIPaymentProcessor_v1(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor_v1 = address(new PaymentProcessor_v1_Mock());

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            address(newPaymentProcessor_v1)
        );

        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        orchestrator.executeSetPaymentProcessor(address(newPaymentProcessor_v1));
    }

    function testExecuteSetpaymentProcessorWithTimelock_SupportsIPaymentProcessor_v2(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor_v2 = address(new PaymentProcessor_v2_Mock());

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            address(newPaymentProcessor_v2)
        );

        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        orchestrator.executeSetPaymentProcessor(address(newPaymentProcessor_v2));
    }

    function testExecuteSetpaymentProcessorWithTimelock_SupportsIPaymentProcessor_v3(
    ) public {
        address[] memory modules;

        // Initialize orchestrator.
        orchestrator.init(
            1,
            address(moduleFactory),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor_v3 = address(new PaymentProcessor_v3_Mock());

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            address(newPaymentProcessor_v3)
        );

        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        orchestrator.executeSetPaymentProcessor(address(newPaymentProcessor_v3));
    }

    function testInitiateAndExecuteSetPaymentProcessor(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor = address(new PaymentProcessor_v3_Mock());

        orchestrator.initiateSetPaymentProcessorWithTimelock(
            newPaymentProcessor
        );
        vm.warp(block.timestamp + orchestrator.MODULE_UPDATE_TIMELOCK());

        // set the new payment processor module
        vm.expectEmit(true, true, true, true);
        emit IOrchestrator_v2.PaymentProcessorUpdated(newPaymentProcessor);
        orchestrator.executeSetPaymentProcessor(newPaymentProcessor);
        assertTrue(
            address(orchestrator.paymentProcessor()) == newPaymentProcessor
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testInitiateSetPaymentProcessorWithTimelock_FailsIfWrongModuleType(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor = address(0x8888);

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                newPaymentProcessor
            )
        );
        orchestrator.initiateSetPaymentProcessorWithTimelock(
            newPaymentProcessor
        );

        assertTrue(orchestrator.paymentProcessor() == paymentProcessor);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testExecuteSetPaymentProcessor_FailsIfWrongModuleType(
        uint orchestratorId,
        uint moduleAmount
    ) public {
        types.assumeValidOrchestratorId(orchestratorId);
        // Initialize orchestrator.
        orchestrator.init(
            orchestratorId,
            address(moduleFactory),
            createModules(moduleAmount),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        // Create new payment processor module
        address newPaymentProcessor = address(0x8888);

        // set the new payment processor module. First the verification function reverts, then the setter.
        vm.expectRevert();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                newPaymentProcessor
            )
        );
        orchestrator.executeSetPaymentProcessor(newPaymentProcessor);

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

        address currentAuthorizer = address(orchestrator.authorizer());

        vm.expectRevert(
            IOrchestrator_v2.Orchestrator__InvalidRemovalOfAuthorizer.selector
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
            IOrchestrator_v2
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
            IOrchestrator_v2
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
            address(moduleFactory),
            new address[](0),
            fundingManager,
            authorizer,
            paymentProcessor,
            governor
        );

        address currentAuthorizer = address(orchestrator.authorizer());

        vm.expectRevert(
            IOrchestrator_v2.Orchestrator__InvalidRemovalOfAuthorizer.selector
        );
        orchestrator.executeRemoveModule(currentAuthorizer);
    }

    function testExecuteRemoveModule_failsGivenModuleAddressIsCurrentFundingManager(
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
            IOrchestrator_v2
                .Orchestrator__InvalidRemovalOfFundingManager
                .selector
        );
        orchestrator.executeRemoveModule(currentFundingManager);
    }

    function testExecuteRemoveModule_failsGivenModuleAddressIsCurrentPaymentProcessor(
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
            IOrchestrator_v2
                .Orchestrator__InvalidRemovalOfPaymentProcessor
                .selector
        );
        orchestrator.executeRemoveModule(currentPaymentProcessor);
    }

    // ========================================================================
    // Internal Functions

    // ------------------------------------------------------------------------
    // Internal - Enforce Module Interface Check

    function test_enforcePrivilegedModuleInterfaceCheck_failsIfContractIsNotAModule(
    ) public {
        // Create a mock that mocks ERC165
        ERC165InterfaceMock iMock = new ERC165InterfaceMock();
        address contractAddr = address(iMock);

        // if the contract address is not a module, it should revert
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforcePrivilegedModuleInterfaceCheck_exposed(
                contractAddr, new bytes4[](0)
            );
        }
    }

    function test_enforcePrivilegedModuleInterfaceCheck_succeedsIfContractIsEitherModule_v1Or_v2(
    ) public {
        // Create a mock that mocks ERC165
        ERC165InterfaceMock iMock = new ERC165InterfaceMock();
        address contractAddr = address(iMock);

        // We need to check for a single interface for the call to be successful
        bytes4[] memory privilegedInterfaceIds = new bytes4[](1);
        privilegedInterfaceIds[0] = bytes4(0);
        iMock.registerInterface(bytes4(0));

        // if the contract address implements IModule_v1 it should not revert
        {
            iMock.registerInterface(type(IModule_v1).interfaceId);
            orchestrator._enforcePrivilegedModuleInterfaceCheck_exposed(
                contractAddr, privilegedInterfaceIds
            );
            iMock.unregisterInterface(type(IModule_v1).interfaceId);
        }
        // if the contract address implements IModule_v2 it should not revert
        {
            iMock.registerInterface(type(IModule_v2).interfaceId);
            orchestrator._enforcePrivilegedModuleInterfaceCheck_exposed(
                contractAddr, privilegedInterfaceIds
            );
        }
    }

    function test_enforceNonPrivilegedModuleInterfaceCheck_failsGivenModuleIsPrivileged(
    ) public {
        // Create a mock that mocks ERC165
        ERC165InterfaceMock iMock = new ERC165InterfaceMock();
        address contractAddr = address(iMock);

        // if the contract address is not a module, it should revert
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
        }

        // If the contract address is Module_v1, it should not revert
        {
            iMock.registerInterface(type(IModule_v1).interfaceId);
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
            iMock.unregisterInterface(type(IModule_v1).interfaceId);
        }

        // If the contract address is Module_v2, it should not revert
        {
            iMock.registerInterface(type(IModule_v2).interfaceId);
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
            iMock.unregisterInterface(type(IModule_v2).interfaceId);
        }

        // All the following tests will revert automatically if the contract address is not a module
        iMock.registerInterface(type(IModule_v2).interfaceId);

        // If the contract address is IAuthorizer_v1, it should revert
        {
            iMock.registerInterface(type(IAuthorizer_v1).interfaceId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
            iMock.unregisterInterface(type(IAuthorizer_v1).interfaceId);
        }

        // If the contract address is IAuthorizer_v2, it should revert
        {
            iMock.registerInterface(type(IAuthorizer_v2).interfaceId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
            iMock.unregisterInterface(type(IAuthorizer_v2).interfaceId);
        }

        // If the contract address is IFundingManager_v1, it should revert
        {
            iMock.registerInterface(type(IFundingManager_v1).interfaceId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
            iMock.unregisterInterface(type(IFundingManager_v1).interfaceId);
        }

        // If the contract address is IPaymentProcessor_v1, it should revert
        {
            iMock.registerInterface(type(IPaymentProcessor_v1).interfaceId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
            iMock.unregisterInterface(type(IPaymentProcessor_v1).interfaceId);
        }

        // If the contract address is IPaymentProcessor_v2, it should revert
        {
            iMock.registerInterface(type(IPaymentProcessor_v2).interfaceId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
            iMock.unregisterInterface(type(IPaymentProcessor_v2).interfaceId);
        }

        // If the contract address is IPaymentProcessor_v3, it should revert
        {
            iMock.registerInterface(type(IPaymentProcessor_v3).interfaceId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrchestrator_v2.Orchestrator__InvalidModuleType.selector,
                    contractAddr
                )
            );
            orchestrator._enforceNonPrivilegedModuleInterfaceCheck_exposed(
                contractAddr
            );
        }
    }

    // ------------------------------------------------------------------------
    // Internal - Authorization

    /*
    Test: _checkAuthorization_
    └── Given: Authorizer hasPermission() is mocked
        ├── When: _checkAuthorization_ is called
        └── And: Authorizer hasPermission() returns false
            ├── Then: It should forward the function selector properly
            └── And: The function should revert
    */
    function test_checkAuthorization_hasPermissionMocked(
        bool hasPermission_,
        address caller_,
        bytes calldata data_
    ) public {
        vm.assume(data_.length >= 4);
        // Assume that caller is not the module as it is the default admin
        vm.assume(caller_ != address(this));

        // Turn off that every caller has permission for every permissioned function
        authorizer.setAllAuthorized(false);

        authorizer.setHasPermission(
            caller_, address(orchestrator), bytes4(data_[0:4]), hasPermission_
        );

        if (!hasPermission_) {
            vm.expectRevert(
                IOrchestrator_v2.Orchestrator__NotPermissioned.selector
            );
        }

        orchestrator._checkAuthorization_exposed(caller_, data_);
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function createModules(uint amount)
        internal
        returns (address[] memory modules)
    {
        if (amount > 50) {
            amount = 50;
        }

        modules = new address[](amount);
        for (uint i = 0; i < amount; i++) {
            modules[i] = address(new Module_v2_Mock());
        }
    }
}
