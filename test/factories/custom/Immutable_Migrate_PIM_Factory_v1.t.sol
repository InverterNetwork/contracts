// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Test Framework
import "forge-std/Test.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {EventHelpers} from "test/utils/helpers/EventHelpers.sol";

// OpenZeppelin Contracts
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Core Protocol Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IImmutable_Migrate_PIM_Factory_v1} from
    "src/factories/interfaces/IImmutable_Migrate_PIM_Factory_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

// Token Contracts
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// Bonding Curve Contracts
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

// Bonding Curve Interfaces
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

// Factory Implementation
import {Immutable_Migrate_PIM_Factory_v1} from
    "src/factories/custom/Immutable_Migrate_PIM_Factory_v1.sol";

// Liquidity Migration
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

contract Immutable_Migrate_PIM_Factory_v1Test is E2ETest {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev    Get address of module with given title.
    function _getModuleAddressByTitle(
        address[] memory modules,
        string memory title
    ) private view returns (address) {
        for (uint i = 0; i < modules.length; i++) {
            if (
                keccak256(bytes(Module_v1(modules[i]).title()))
                    == keccak256(bytes(title))
            ) {
                return modules[i];
            }
        }
        revert
            IImmutable_Migrate_PIM_Factory_v1
            .PIM_WorkflowFactory__ModuleNotFound();
    }

    // Contract instance under test
    IImmutable_Migrate_PIM_Factory_v1 factory;
    EventHelpers eventHelpers;

    IOrchestrator_v1 orchestrator;
    ERC20Issuance_v1 issuanceToken;
    FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager;
    ILM_PC_MigrateLiquidity_UniswapV2_v1 logicModule;

    // Workflow configuration
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;

    // Bonding Curve properties
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveBase_v1.IssuanceToken issuanceTokenParams;
    uint initialPurchaseAmount = 1000e18;
    uint initialIssuuanceSupply = 122_727_272_727_272_727_272_727;
    uint initialCollateralSupply = 3_163_408_614_166_851_161;
    uint32 reserveRatio = 160_000;

    // Addresses for testing
    address workflowAdmin = vm.addr(420);
    address factoryDeployer = vm.addr(1);
    address workflowDeployer = vm.addr(2);
    address mockTrustedForwarder = vm.addr(3);
    address alice = vm.addr(0xA11CE);

    // Parameters for liquidity migration
    uint constant COLLATERAL_MIGRATION_THRESHOLD = 2000e18;
    uint constant COLLATERAL_MIGRATION_AMOUNT = 2000e18;
    uint constant BUY_FROM_FUNDING_MANAGER_AMOUNT = 2000e18;

    // Uniswap
    address uniswapFactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Factory uniswapFactory;
    IUniswapV2Router02 uniswapRouter;

    function setUp() public override {
        super.setUp();

        // Step 1: Deploy Uniswap contracts
        vm.etch(uniswapFactoryAddress, uniswapV2FactoryBytecode);
        vm.etch(uniswapRouterAddress, uniswapV2Router02Bytecode);
        uniswapFactory = IUniswapV2Factory(uniswapFactoryAddress);
        uniswapRouter = IUniswapV2Router02(uniswapRouterAddress);

        // Step 2: Deploy factory and event helpers
        factory = new Immutable_Migrate_PIM_Factory_v1(
            address(orchestratorFactory), mockTrustedForwarder
        );
        eventHelpers = new EventHelpers();

        // Step 3: Configure Orchestrator Workflow
        workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Step 4: Set up authorizer and payment processor modules
        setUpRoleAuthorizer();
        authorizerConfig = IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(address(workflowAdmin))
        );
        setUpSimplePaymentProcessor();
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
        );

        // Step 5: Set up logic module for liquidity migration
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
                        lpTokenRecipientAddress: alice
                    })
                )
            )
        );

        // Step 6: Set up bonding curve properties for Funding Manager
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

        // Step 7: Set issuance token parameters and approve tokens for factory
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        // Step 8: Mint and approve tokens for factory
        uint mintAmount = 1_000_000_000_000e18; // 1 trillion tokens

        token.mint(address(this), mintAmount);
        token.approve(address(factory), mintAmount);

        // Step 9: Mint tokens for Alice
        token.mint(alice, mintAmount);
    }

    function testCreatePIMWorkflow() public {
        vm.recordLogs();

        // Step 1: Deploy orchestrator
        orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );

        // Step 2: Set up funding manager
        fundingManager = FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        // Step 3: Verify PIMWorkflowCreated event is emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bool emitted, bytes32 eventTopic) = eventHelpers.getEventTopic(
            IImmutable_Migrate_PIM_Factory_v1.PIMWorkflowCreated.selector,
            logs,
            2
        );
        assertTrue(emitted);

        // Step 4: Get issuance token address from event and verify configuration
        address issuanceTokenAddress =
            eventHelpers.getAddressFromTopic(eventTopic);

        // Step 5: Set issuance token
        issuanceToken = ERC20Issuance_v1(issuanceTokenAddress);

        // Step 6: Get and set logic module
        logicModule = ILM_PC_MigrateLiquidity_UniswapV2_v1(
            _getModuleAddressByTitle(
                orchestrator.listModules(),
                "LM_PC_MigrateLiquidity_UniswapV2_v1"
            )
        );

        // Step 7: Verify issuance token configuration
        assertFalse(issuanceToken.allowedMinters(address(factory)));
        assertTrue(issuanceToken.allowedMinters(address(fundingManager)));
        assertEq(issuanceToken.owner(), address(0));
        assertGt(issuanceToken.balanceOf(workflowAdmin), 0);
        assertEq(
            token.balanceOf(address(fundingManager)), initialPurchaseAmount
        );
    }

    function testWithdrawPimFee() public {
        // Step 1: First deploy the workflow
        testCreatePIMWorkflow();

        // Step 2: Verify withdrawal events when called by fee recipient
        vm.startPrank(workflowAdmin);
        vm.expectEmit(true, true, true, false);
        // Step 3: Expect ProjectCollateralFeeWithdrawn event
        emit IBondingCurveBase_v1.ProjectCollateralFeeWithdrawn(
            address(this), 0
        );
        // Step 4: Verify claimable fees
        uint claimableFees = fundingManager.projectCollateralFeeCollected();
        vm.expectEmit(true, false, false, false);
        // Step 5: Expect PimFeeClaimed event
        emit IImmutable_Migrate_PIM_Factory_v1.PimFeeClaimed(
            address(fundingManager), address(this), alice, claimableFees
        );
        // Step 6: Withdraw fee
        factory.withdrawPimFee(address(fundingManager), alice);
        vm.stopPrank();
    }

    function testWithdrawPimFee__FailsIfCallerIsNotPimFeeRecipient() public {
        // Step 1: Check that non-recipient address cannot withdraw fee
        vm.expectRevert(
            abi.encodeWithSelector(
                IImmutable_Migrate_PIM_Factory_v1
                    .PIM_WorkflowFactory__OnlyPimFeeRecipient
                    .selector
            )
        );
        // Step 2: Attempt to withdraw fee
        vm.prank(alice);
        factory.withdrawPimFee(address(fundingManager), alice);
    }

    function testMigrateLiquidity() public {
        // Step 1: First deploy the workflow
        testCreatePIMWorkflow();

        vm.startPrank(alice);
        // Step 2: Approve funding manager to spend tokens
        token.approve(address(fundingManager), BUY_FROM_FUNDING_MANAGER_AMOUNT);

        // Step 3: Buy from funding manager to reach migration threshold
        uint minAmountOut = fundingManager.calculatePurchaseReturn(
            BUY_FROM_FUNDING_MANAGER_AMOUNT
        );
        fundingManager.buy(BUY_FROM_FUNDING_MANAGER_AMOUNT, minAmountOut);

        // Step 4: Verify that the migration threshold has been reached
        assertTrue(logicModule.isMigrationReady(), "Migration should be ready");

        // Step 5: Execute migration
        ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationResult memory
            migrationResult = factory.executeMigration();
        assertTrue(logicModule.getExecuted(), "Migration should be executed");

        vm.stopPrank();

        // Step 5: Verify that the migration was successful
        assertEq(
            IERC20(migrationResult.lpTokenAddress).balanceOf(alice),
            migrationResult.lpTokenAmount,
            "LP token balance mismatch"
        );

        // Step 6: Verify the curve buy and sell are closed
        assertFalse(fundingManager.buyIsOpen(), "Buy should be closed");
        assertFalse(fundingManager.sellIsOpen(), "Sell should be closed");
    }
}
