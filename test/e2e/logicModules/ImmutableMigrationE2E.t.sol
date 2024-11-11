// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/Vm.sol"; // Add this import statement

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {Immutable_PIM_Factory_v1} from
    "src/factories/custom/Immutable_PIM_Factory_v1.sol";
import {IImmutable_PIM_Factory_v1} from
    "src/factories/interfaces/IImmutable_PIM_Factory_v1.sol";

// Uniswap Dependencies

// SuT
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {LM_ImmutableMigration_v1} from
    "src/modules/logicModule/LM_ImmutableMigration_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract LM_ImmutableMigration_v1E2E is E2ETest {
    // Immutable PIM Factory
    Immutable_PIM_Factory_v1 factory;

    // Orchestrator Configurations
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveBase_v1.IssuanceToken issuanceTokenParams;
    uint initialPurchaseAmount = 0 ether;

    // Bonding Curve Parameters
    uint initialIssuanceSupply = 122_727_272_727_272_727_272_727;
    uint initialCollateralSupply = 3_163_408_614_166_851_161;
    uint32 reserveRatio = 160_000;

    // Constants
    uint constant COLLATERAL_MIGRATION_THRESHOLD = 1000e18;
    uint constant COLLATERAL_MIGRATION_AMOUNT = 1000e18;
    uint constant BUY_FROM_FUNDING_MANAGER_AMOUNT = 1000e18;

    // Test variables
    IOrchestrator_v1 orchestrator;
    LM_ImmutableMigration_v1 migrationModule;
    ERC20Issuance_v1 issuanceToken;

    function setUp() public override {
        super.setUp();

        // deploy new factory
        factory = new Immutable_PIM_Factory_v1(
            address(orchestratorFactory), address(0)
        );

        // Orchestrator/Workflow config
        workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Authorizer
        setUpRoleAuthorizer();
        authorizerConfig = IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(address(0x420))
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
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
            initialIssuanceSupply: initialIssuanceSupply,
            initialCollateralSupply: initialCollateralSupply
        });

        fundingManagerConfig = IOrchestratorFactory_v1.ModuleConfig(
            bancorVirtualSupplyBondingCurveFundingManagerMetadata,
            abi.encode(address(0), bcProperties, token)
        );

        // Logic Module: Immutable Migration
        setUpLM_ImmutableMigration_v1();
        logicModuleConfigs.push(
            IOrchestratorFactory_v1.ModuleConfig(
                LM_ImmutableMigration_v1Metadata,
                abi.encode(COLLATERAL_MIGRATION_THRESHOLD)
            )
        );

        // Put issuance token params in storage
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        // start recording logs
        vm.recordLogs();

        orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );

        issuanceToken = ERC20Issuance_v1(
            IBondingCurveBase_v1(address(orchestrator.fundingManager()))
                .getIssuanceToken()
        );

        // Get address of migration module and issuance token
        address[] memory modules = orchestrator.listModules();
        for (uint i = 0; i < modules.length; i++) {
            try LM_ImmutableMigration_v1(modules[i]).migrationThreshold() {
                migrationModule = LM_ImmutableMigration_v1(modules[i]);
                break;
            } catch {}
        }

        console.log("migrationModule: %s", address(migrationModule));
    }

    function test_buyForUpTo_BelowThreshold(uint amountIn) public {
        if (amountIn == 0) return;

        // Bound input to range below threshold
        amountIn = bound(amountIn, 1, COLLATERAL_MIGRATION_THRESHOLD - 1);

        mintAndApprove(amountIn);

        // Record balances before
        uint buyerTokenBalanceBefore = token.balanceOf(address(this));
        uint buyerIssuanceBalanceBefore = issuanceToken.balanceOf(address(this));

        // Execute buy
        migrationModule.buyForUpTo(amountIn, address(this));

        // Verify balances changed correctly
        assertLt(
            token.balanceOf(address(this)),
            buyerTokenBalanceBefore,
            "Token balance should decrease"
        );
        assertGt(
            issuanceToken.balanceOf(address(this)),
            buyerIssuanceBalanceBefore,
            "Issuance balance should increase"
        );
    }

    function test_buyForUpTo_AtAboveThreshold(uint amountIn) public {
        // Bound input to be at or above threshold
        amountIn = bound(
            amountIn,
            COLLATERAL_MIGRATION_THRESHOLD + 1,
            10_000_000_000_000 ether
        );
        mintAndApprove(amountIn);

        vm.expectEmit(true, true, true, true);
        emit IBondingCurveBase_v1.BuyingDisabled();
        migrationModule.buyForUpTo(amountIn, address(this));

        // assertFalse(
        //     FM_BC_Bancor_Redeeming_VirtualSupply_v1(address(orchestrator.fundingManager()))
        //         .buyIsOpen(),
        //     "Buying should be closed"
        // );
    }

    // // Test
    // function test_e2e_MigrateLiquidityLifecycle() public {
    //     //--------------------------------------------------------------------------
    //     // Orchestrator Initialization
    //     //--------------------------------------------------------------------------

    //     // Set WorkflowConfig
    //     IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
    //     IOrchestratorFactory_v1.WorkflowConfig({
    //         independentUpdates: false,
    //         independentUpdateAdmin: address(0)
    //     });

    //     // Set Orchestrator
    //     IOrchestrator_v1 orchestrator =
    //         _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

    //     // Set FundingManager
    //     FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
    //     FM_BC_Bancor_Redeeming_VirtualSupply_v1(
    //         address(orchestrator.fundingManager())
    //     );

    //     // Find and Set Migration Manager
    //     LM_PC_MigrateLiquidity_UniswapV2_v1 migrationManager;
    //     address[] memory modulesList = orchestrator.listModules();
    //     for (uint i; i < modulesList.length; ++i) {
    //         if (
    //             ERC165Upgradeable(modulesList[i]).supportsInterface(
    //                 type(ILM_PC_MigrateLiquidity_UniswapV2_v1).interfaceId
    //             )
    //         ) {
    //             migrationManager =
    //                 LM_PC_MigrateLiquidity_UniswapV2_v1(modulesList[i]);
    //             break;
    //         }
    //     }

    //     // Test Lifecycle
    //     //--------------------------------------------------------------------------

    //     // 1. Set FundingManager as Minter
    //     issuanceToken.setMinter(address(fundingManager), true);

    //     // 1.1. Set Migration Manager As Minter
    //     issuanceToken.setMinter(address(migrationManager), true);

    //     // 2. Mint Collateral To Buy From the FundingManager
    //     token.mint(address(this), BUY_FROM_FUNDING_MANAGER_AMOUNT);

    //     // 3. Calculate Minimum Amount Out
    //     uint buf_minAmountOut = fundingManager.calculatePurchaseReturn(
    //         BUY_FROM_FUNDING_MANAGER_AMOUNT
    //     ); // buffer variable to store the minimum amount out on calls to the buy and sell functions

    //     // 4. Buy from the FundingManager
    //     vm.startPrank(address(this));
    //     {
    //         // 4.1. Approve tokens to fundingManager.
    //         token.approve(
    //             address(fundingManager), BUY_FROM_FUNDING_MANAGER_AMOUNT
    //         );
    //         // 4.2. Deposit tokens, i.e. fund the fundingmanager.
    //         fundingManager.buy(
    //             BUY_FROM_FUNDING_MANAGER_AMOUNT, buf_minAmountOut
    //         );
    //         // 4.3. After the deposit, check that the user has received them
    //         assertTrue(
    //             issuanceToken.balanceOf(address(this)) > 0,
    //             "User should have received issuance tokens after deposit"
    //         );
    //     }
    //     vm.stopPrank();

    //     // 5. Check no pool exists yet
    //     address lpTokenAddress =
    //         uniswapFactory.getPair(address(token), address(issuanceToken));

    //     assertEq(lpTokenAddress, address(0), "Pool should not exist yet");

    //     // 6. Set migration manager instance
    //     ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationConfig memory
    //         migration = migrationManager.getMigrationConfig();

    //     ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationResult memory
    //         migrationResult;

    //     // 7. Execute migration
    //     vm.startPrank(address(this));
    //     migrationResult = migrationManager.executeMigration();
    //     vm.stopPrank();

    //     bool executed = migrationManager.getExecuted();

    //     // 8. Verify pool creation and liquidity
    //     lpTokenAddress =
    //         uniswapFactory.getPair(address(token), address(issuanceToken));
    //     assertTrue(lpTokenAddress != address(0), "Pool should exist");

    //     // 9.1. Get pair
    //     IUniswapV2Pair pair = IUniswapV2Pair(lpTokenAddress);

    //     // 9.2. Get reserves
    //     (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

    //     // 9.3. Verify reserves based on token ordering
    //     if (pair.token0() == address(token)) {
    //         assertGt(reserve0, 0, "Token reserves should be positive");
    //         assertGt(reserve1, 0, "IssuanceToken reserves should be positive");
    //     } else {
    //         assertGt(reserve0, 0, "IssuanceToken reserves should be positive");
    //         assertGt(reserve1, 0, "Token reserves should be positive");
    //     }

    //     // 10. Verify migration completion
    //     migration = migrationManager.getMigrationConfig();
    //     assertTrue(executed, "Migration should be marked as executed");

    //     // 11. Verify LP tokens are received by the migration manager
    //     assertGt(
    //         IERC20(migrationResult.lpTokenAddress).balanceOf(address(this)),
    //         0,
    //         "Script should have received LP tokens"
    //     );
    // }

    //--------------------------------------------------------------------------
    // Utils
    //--------------------------------------------------------------------------

    function mintAndApprove(uint amount) internal {
        token.mint(address(this), amount);
        token.approve(address(migrationModule), amount);
    }
}
