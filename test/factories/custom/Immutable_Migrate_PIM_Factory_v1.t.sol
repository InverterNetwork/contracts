// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IImmutable_Migrate_PIM_Factory_v1} from
    "src/factories/interfaces/IImmutable_Migrate_PIM_Factory_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {Immutable_Migrate_PIM_Factory_v1} from
    "src/factories/custom/Immutable_Migrate_PIM_Factory_v1.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {EventHelpers} from "test/utils/helpers/EventHelpers.sol";
import {ILM_PC_MigrateLiquidity_UniswapV2_v1} from
    "@lm/LM_PC_MigrateLiquidity_UniswapV2_v1.sol";
// Uniswap Dependencies
import {IUniswapV2Pair} from "@ex/interfaces/uniswap/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@ex/interfaces/uniswap/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@ex/interfaces/uniswap/IUniswapV2Router02.sol";
import {uniswapV2FactoryBytecode} from
    "test/e2e/lib/uniswap/uniswapV2FactoryBytecode.sol";
import {uniswapV2Router02Bytecode} from
    "test/e2e/lib/uniswap/uniswapV2Router02Bytecode.sol";

import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

interface IExtendedBondingCurve is
    IBondingCurveBase_v1,
    IRedeemingBondingCurveBase_v1
{}

contract Immutable_Migrate_PIM_Factory_v1Test is E2ETest {
    // SuT
    IImmutable_Migrate_PIM_Factory_v1 factory;

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

    // Migrate Liquidity
    uint constant COLLATERAL_MIGRATION_THRESHOLD = 1000e18;
    uint constant COLLATERAL_MIGRATION_AMOUNT = 1000e18;
    uint constant BUY_FROM_FUNDING_MANAGER_AMOUNT = 1000e18;
    // Uniswap
    address uniswapFactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Factory uniswapFactory;
    IUniswapV2Router02 uniswapRouter;

    function setUp() public override {
        super.setUp();

        // Step 1: Deploy Uniswap Contracts
        vm.etch(uniswapFactoryAddress, uniswapV2FactoryBytecode);
        vm.etch(uniswapRouterAddress, uniswapV2Router02Bytecode);

        uniswapFactory = IUniswapV2Factory(uniswapFactoryAddress);
        uniswapRouter = IUniswapV2Router02(uniswapRouterAddress);

        // deploy new factory
        factory = new Immutable_Migrate_PIM_Factory_v1(
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

        // Logic Modules: Migrate Liquidity
        setUpLM_PC_MigrateLiquidity_UniswapV2_v1();
        logicModuleConfigs.push(
            IOrchestratorFactory_v1.ModuleConfig(
                LM_PC_MigrateLiquidity_UniswapV2_v1Metadata,
                abi.encode(
                    ILM_PC_MigrateLiquidity_UniswapV2_v1
                        .LiquidityMigrationConfig({
                        collateralMigrationAmount: COLLATERAL_MIGRATION_AMOUNT,
                        collateralMigrateThreshold: COLLATERAL_MIGRATION_THRESHOLD,
                        dexRouterAddress: address(uniswapRouter),
                        lpTokenRecipientAddress: address(this)
                    })
                )
            )
        );

        // Funding Manager: Bancor Virtual Supply
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
            bancorVirtualSupplyBondingCurveFundingManagerMetadata,
            abi.encode(address(0), bcProperties, token)
        );

        // Put issuance token params in storage
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        // mint collateral token to deployer and approve to factory
        token.mint(address(this), type(uint).max);
        token.approve(address(factory), type(uint).max);
    }

    /* Test createPIMWorkflow
        ├── given an unrestricted bonding curve
        |   └── when called
        |       ├── then it deploys an issuance token and a workflow
        |       ├── then it executes initial purchase
        |       ├── then it grants issuanceToken minting rights to bonding curve
        |       ├── then it renounces ownership over issuance token
        |       ├── then it revokes orchestrator admin rights and transfers them to factory
        |       └── then it emits a PIMWorkflowCreated event YES
        └── given the initiator has not been set
            └── when called
                └── then it reverts
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
            IImmutable_Migrate_PIM_Factory_v1.PIMWorkflowCreated.selector,
            logs,
            2
        );
        address issuanceTokenAddress =
            eventHelpers.getAddressFromTopic(eventTopic);

        // CHECK: PIMWorkflowCreated event is emitted
        assertTrue(emitted);

        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(issuanceTokenAddress);
        address fundingManager = address(orchestrator.fundingManager());

        // CHECK: factory DOES NOT have minting rights on token anymore
        assertFalse(issuanceToken.allowedMinters(address(factory)));
        // CHECK: bonding curve module HAS minting rights on token
        assertTrue(issuanceToken.allowedMinters(fundingManager));
        // CHECK: issuance token is renounced
        assertEq(issuanceToken.owner(), address(0));
        // CHECK: factory HAS admin rights over workflow
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertTrue(
            orchestrator.authorizer().hasRole(adminRole, address(factory))
        );
        // CHECK: initial purchase was executed
        assertGt(issuanceToken.balanceOf(workflowAdmin), 0);
        assertEq(token.balanceOf(fundingManager), initialPurchaseAmount);
    }

    function testCreatePIMWorkflow_WithoutInitiator() public {
        IOrchestratorFactory_v1.ModuleConfig memory invalidAuthorizerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(address(0))
        );

        vm.expectRevert(
            IImmutable_Migrate_PIM_Factory_v1
                .PIM_WorkflowFactory__InvalidZeroAddress
                .selector
        );
        factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            invalidAuthorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );
    }

    /* Test testWithdrawPimFee
        ├── given the msg.sender is the fee recipient
        |   └── when called
        |       └── then it emits fee claim events on bc and factory
        └── given the msg.sender is NOT the fee recipient
            └── when called
                └── then it reverts   
    */

    function testWithdrawPimFee() public {
        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );
        address fundingManager = address(orchestrator.fundingManager());
        vm.startPrank(workflowAdmin);
        // CHECK: bonding curve EMITS event for fee withdrawal
        vm.expectEmit(true, true, true, false);
        emit IBondingCurveBase_v1.ProjectCollateralFeeWithdrawn(
            address(this), 0
        );
        uint claimableFees =
            IBondingCurveBase_v1(fundingManager).projectCollateralFeeCollected();
        vm.expectEmit(true, false, false, false);
        emit IImmutable_Migrate_PIM_Factory_v1.PimFeeClaimed(
            fundingManager, address(this), alice, claimableFees
        );
        factory.withdrawPimFee(fundingManager, alice);
        vm.stopPrank();
    }

    function testWithdrawPimFee__FailsIfCallerIsNotPimFeeRecipient() public {
        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );
        address fundingManager = address(orchestrator.fundingManager());

        // CHECK: withdrawal REVERTS if caller IS NOT the fee recipient
        vm.expectRevert(
            abi.encodeWithSelector(
                IImmutable_Migrate_PIM_Factory_v1
                    .PIM_WorkflowFactory__OnlyPimFeeRecipient
                    .selector
            )
        );
        vm.prank(alice);
        factory.withdrawPimFee(fundingManager, alice);
    }

    function testMigrateLiquidity() public {
        // Create workflow and get orchestrator
        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );

        // Get addresses from orchestrator
        address fundingManager = address(orchestrator.fundingManager());
        address issuanceTokenAddress =
            address(IBondingCurveBase_v1(fundingManager).getIssuanceToken());

        // Buy from funding manager to reach migration threshold
        vm.startPrank(workflowAdmin);
        token.mint(workflowAdmin, BUY_FROM_FUNDING_MANAGER_AMOUNT);
        token.approve(fundingManager, BUY_FROM_FUNDING_MANAGER_AMOUNT);
        IBondingCurveBase_v1(fundingManager).buy(
            BUY_FROM_FUNDING_MANAGER_AMOUNT,
            1 // min amount out
        );
        vm.stopPrank();

        // Verify no pool exists yet
        address lpTokenAddress =
            uniswapFactory.getPair(address(token), issuanceTokenAddress);
        assertEq(lpTokenAddress, address(0), "Pool should not exist yet");

        // Execute migration
        ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationResult memory
            result = factory.executeMigration();

        // Verify pool creation and liquidity
        lpTokenAddress =
            uniswapFactory.getPair(address(token), issuanceTokenAddress);
        assertTrue(lpTokenAddress != address(0), "Pool should exist");

        // Get pair and verify reserves
        IUniswapV2Pair pair = IUniswapV2Pair(lpTokenAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        if (pair.token0() == address(token)) {
            assertGt(reserve0, 0, "Token reserves should be positive");
            assertGt(reserve1, 0, "IssuanceToken reserves should be positive");
        } else {
            assertGt(reserve0, 0, "IssuanceToken reserves should be positive");
            assertGt(reserve1, 0, "Token reserves should be positive");
        }

        // Verify LP tokens are received
        assertGt(
            IERC20(result.lpTokenAddress).balanceOf(address(this)),
            0,
            "Should have received LP tokens"
        );

        // Verify bonding curve is closed
        IExtendedBondingCurve bc = IExtendedBondingCurve(fundingManager);
        assertFalse(bc.buyIsOpen(), "Buy should be closed");
        assertFalse(bc.sellIsOpen(), "Sell should be closed");

        // Try to execute again
        vm.expectRevert(
            abi.encodeWithSelector(
                Module_v1
                    .Module__LM_PC_MigrateLiquidity__AlreadyExecuted
                    .selector
            )
        );
        factory.executeMigration();

        // Try to execute migration without reaching threshold
        vm.expectRevert(
            abi.encodeWithSelector(
                Module_v1
                    .Module__LM_PC_MigrateLiquidity__ThresholdNotReached
                    .selector
            )
        );
        factory.executeMigration();
    }
}
