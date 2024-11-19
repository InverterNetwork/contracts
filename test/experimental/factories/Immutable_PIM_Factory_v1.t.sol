// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IImmutable_PIM_Factory_v1} from
    "src/experimental/factories/interfaces/IImmutable_PIM_Factory_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {Immutable_PIM_Factory_v1} from
    "src/experimental/factories/Immutable_PIM_Factory_v1.sol";
import {ExtendedE2ETest} from "test/experimental/e2e/ExtendedE2ETest.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {EventHelpers} from "test/utils/helpers/EventHelpers.sol";

import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {LM_ImmutableMigration_v1} from
    "src/experimental/modules/ImmutableMigration/LM_ImmutableMigration_v1.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

contract Immutable_PIM_Factory_v1Test is ExtendedE2ETest {
    // SuT
    Immutable_PIM_Factory_v1 factory;

    // helpers
    EventHelpers eventHelpers;

    // Deployment Parameters
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveBase_v1.IssuanceToken issuanceTokenParams;
    uint initialPurchaseAmount = 100 ether;

    // addresses
    address workflowAdmin = vm.addr(420);
    address factoryDeployer = vm.addr(1);
    address workflowDeployer = vm.addr(2);
    address mockTrustedForwarder = vm.addr(3);
    address alice = vm.addr(0xA11CE);

    // bc params
    uint initialIssuuanceSupply = 122_727_272_727_272_727_272_727;
    uint initialCollateralSupply = 3_163_408_614_166_851_161;
    uint32 reserveRatio = 160_000;

    // Add constant for migration threshold
    uint COLLATERAL_MIGRATION_THRESHOLD = 10_000 ether;

    function setUp() public override {
        super.setUp();

        // deploy new factory
        factory = new Immutable_PIM_Factory_v1(
            address(orchestratorFactory), mockTrustedForwarder
        );

        eventHelpers = new EventHelpers();

        // Orchestrator/Workflow config
        workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Authorizer
        setUpRoleAuthorizer();
        authorizerConfig = IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(address(workflowAdmin))
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
        );

        // Replace bounty manager setup with ImmutableMigration setup
        setUpPaymentRouter();
        logicModuleConfigs.push(
            IOrchestratorFactory_v1.ModuleConfig(
                paymentRouterMetadata, bytes("")
            )
        );

        // Funding Manager: Restricted Bancor Virtual Supply
        setUpBancorVirtualSupplyBondingCurveFundingManager();
        bcProperties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
            .BondingCurveProperties({
            formula: address(formula),
            reserveRatioForBuying: reserveRatio,
            reserveRatioForSelling: reserveRatio,
            buyFee: 0,
            sellFee: 0,
            buyIsOpen: true,
            sellIsOpen: true,
            initialIssuanceSupply: initialIssuuanceSupply,
            initialCollateralSupply: initialCollateralSupply
        });

        fundingManagerConfig = IOrchestratorFactory_v1.ModuleConfig(
            restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata,
            abi.encode(address(0), bcProperties, token)
        );

        // Put issuance token params in storage
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        token.mint(address(this), initialPurchaseAmount);
        token.approve(address(factory), initialPurchaseAmount);
    }

    /* Test createPIMWorkflow
        └── given a restricted bonding curve
            └── when called
                └── then it deploys an issuance token and a workflow
                └── then it executes initial purchase if initialPurchaseAmount > 0
                └── then it grants issuanceToken minting rights to bonding curve
                └── then it revokes factory minting rights
                └── then it renounces ownership over issuance token
                └── then it grants admin rights to the migration module
                └── then it emits a PIMWorkflowCreated event
    */

    function testCreatePIMWorkflow() public {
        // start recording logs
        vm.recordLogs();

        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // get issuance token address from event
        (bool emitted, bytes32 eventTopic) = eventHelpers.getEventTopic(
            IImmutable_PIM_Factory_v1.PIMWorkflowCreated.selector, logs, 2
        );
        address issuanceTokenAddress =
            eventHelpers.getAddressFromTopic(eventTopic);

        // CHECK: PIMWorkflowCreated event is emitted
        assertTrue(emitted);

        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(issuanceTokenAddress);
        address fundingManager = address(orchestrator.fundingManager());

        assertTrue(
            issuanceToken.allowedMinters(fundingManager),
            "Bonding curve module should have minting rights on token"
        );
        assertEq(
            issuanceToken.owner(),
            address(0),
            "Issuance token should be renounced"
        );
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertTrue(
            orchestrator.authorizer().hasRole(adminRole, address(factory)),
            "Factory should have admin rights over workflow"
        );
        assertGt(
            issuanceToken.balanceOf(workflowAdmin),
            0,
            "Workflow admin should have received issuance tokens"
        );
        assertEq(
            token.balanceOf(fundingManager),
            initialPurchaseAmount,
            "Bonding curve module should have received collateral tokens"
        );
        bytes32 curveAccess = FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            fundingManager
        ).CURVE_INTERACTION_ROLE();
        bytes32 curveInteractionRoleId = orchestrator.authorizer()
            .generateRoleId(fundingManager, curveAccess);
        assertTrue(
            orchestrator.authorizer().checkForRole(
                curveInteractionRoleId, address(factory)
            ),
            "Factory should have curve interaction role"
        );
        // CHECK: factory is allowed minter
        assertTrue(
            issuanceToken.allowedMinters(address(factory)),
            "Factory should be allowed minter"
        );
    }

    function test_buyForUpTo_BelowThreshold(uint amountIn) public {
        console.log("check00");
        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );
        console.log("check01");

        if (amountIn == 0) return;

        // Bound input to range below threshold
        amountIn = bound(amountIn, 1 ether, COLLATERAL_MIGRATION_THRESHOLD - 1);
        address fundingManager = address(orchestrator.fundingManager());
        token.mint(address(this), amountIn);
        token.approve(address(factory), amountIn);

        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(
            IBondingCurveBase_v1(fundingManager).getIssuanceToken()
        );

        // Record balances before
        uint buyerTokenBalanceBefore = token.balanceOf(address(this));
        uint buyerIssuanceBalanceBefore =
            ERC20(issuanceToken).balanceOf(address(this));

        // Execute buy
        factory.buyForUpTo(address(issuanceToken), address(this), amountIn, 1);

        // Verify balances changed correctly
        assertLt(
            token.balanceOf(address(this)),
            buyerTokenBalanceBefore,
            "Token balance should decrease"
        );
        assertGt(
            ERC20(issuanceToken).balanceOf(address(this)),
            buyerIssuanceBalanceBefore,
            "Issuance balance should increase"
        );
    }
}
