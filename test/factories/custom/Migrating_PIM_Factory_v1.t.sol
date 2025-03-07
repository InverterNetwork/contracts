// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// OpenZeppelin
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// Test Utils
import {E2ETest} from "test/e2e/E2ETest.sol";
import {EventHelpers} from "test/utils/helpers/EventHelpers.sol";

// Core Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IMigrating_PIM_Factory_v1} from
    "src/factories/interfaces/IMigrating_PIM_Factory_v1.sol";

// Funding Manager Interfaces
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

// Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {Migrating_PIM_Factory_v1} from
    "src/factories/custom/Migrating_PIM_Factory_v1.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {UniswapV2Adapter} from
    "src/external/immutable-migration/UniswapV2Adapter.sol";
import {LM_PC_Staking_v1} from "src/modules/logicModule/LM_PC_Staking_v1.sol";

// Constants
import {uniswapV2FactoryBytecode} from
    "test/lib/uniswap/uniswapV2FactoryBytecode.sol";
import {uniswapV2Router02Bytecode} from
    "test/lib/uniswap/uniswapV2Router02Bytecode.sol";

// Uniswap constants
address constant uniswapFactoryAddress =
    0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
address constant uniswapRouterAddress =
    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

contract Migrating_PIM_Factory_v1Test is E2ETest {
    // =========================================================================
    // State Variables & Constants
    // =========================================================================

    // Core contracts
    Migrating_PIM_Factory_v1 factory;
    address uniswapAdapter;
    EventHelpers eventHelpers;

    // Configuration objects
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;

    // Bonding curve settings
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveBase_v1.IssuanceToken issuanceTokenParams;
    IMigrating_PIM_Factory_v1.MigrationConfig migrationConfig;

    // Test parameters
    uint constant migrationThreshold = 10 ether;
    uint constant initialIssuuanceSupply = 500_000_000e18;
    uint constant initialCollateralSupply = 3200e18;
    uint32 constant reserveRatio = 333_333;

    // Test addresses
    address workflowAdmin = vm.addr(420);
    address mockTrustedForwarder = vm.addr(3);
    address alice = vm.addr(0xA11CE);

    // =========================================================================
    // Setup
    // =========================================================================

    function setUp() public override {
        super.setUp();

        // Deploy infrastructure
        uniswapAdapter = deployUniswapAdapter();
        factory = new Migrating_PIM_Factory_v1(
            address(orchestratorFactory), mockTrustedForwarder, workflowAdmin
        );
        eventHelpers = new EventHelpers();

        // Configure workflow
        _setupWorkflowConfig();

        // Configure modules
        _setupModuleConfigs();

        // Configure bonding curve
        _setupBondingCurveConfig();

        // Configure migration
        _setupMigrationConfig(false);

        vm.prank(workflowAdmin);
        postSetup(0);
    }

    // =========================================================================
    // Test Cases: Workflow Creation
    // =========================================================================

    /// @notice Tests basic workflow creation with immutable configuration
    /// @dev Verifies:
    ///      - Correct role assignments
    ///      - Token minting permissions
    ///      - Initial token distributions
    ///      - Admin role configurations
    function testCreatePIMWorkflow() public {
        _setupMigrationConfig(true);

        uint initialPurchaseAmount = 1 ether;

        token.mint(address(this), initialPurchaseAmount);
        token.approve(address(factory), initialPurchaseAmount);

        // Post setup
        (
            IOrchestrator_v1 orchestrator,
            ERC20Issuance_v1 issuanceToken,
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager
        ) = postSetup(initialPurchaseAmount);

        // Verify bonding curve has minting rights
        assertTrue(
            issuanceToken.allowedMinters(address(fundingManager)),
            "Bonding curve should have minting rights"
        );

        // Verify admin roles
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertTrue(
            orchestrator.authorizer().hasRole(adminRole, address(factory)),
            "Factory should have admin rights"
        );

        if (!migrationConfig.isImmutable) {
            assertTrue(
                orchestrator.authorizer().hasRole(adminRole, workflowAdmin),
                "Workflow admin should have admin rights"
            );
        }

        // Verify token distribution
        assertGt(
            issuanceToken.balanceOf(workflowAdmin),
            0,
            "Admin should have issuance tokens"
        );

        assertEq(
            token.balanceOf(address(fundingManager)),
            initialPurchaseAmount - initialPurchaseAmount / 100, // 1% protocol fee
            "Funding manager should have collateral tokens"
        );

        // Verify roles
        bytes32 curveAccess = fundingManager.CURVE_INTERACTION_ROLE();
        bytes32 curveInteractionRoleId = orchestrator.authorizer()
            .generateRoleId(address(fundingManager), curveAccess);
        assertTrue(
            orchestrator.authorizer().checkForRole(
                curveInteractionRoleId, address(factory)
            ),
            "Factory should have curve interaction role"
        );

        assertTrue(
            issuanceToken.allowedMinters(address(factory)),
            "Factory should be allowed minter"
        );
    }

    // =========================================================================
    // Test Cases: Trading Operations
    // =========================================================================

    /// @notice Tests buying tokens below migration threshold
    /// @dev Verifies:
    ///      - Token balance changes
    ///      - Bonding curve state remains unchanged
    ///      - Graduation state remains false
    function test_buyForUpTo_BelowThreshold() public {
        _setupMigrationConfig(true);

        // Post setup
        (
            ,
            ERC20Issuance_v1 issuanceToken,
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager
        ) = postSetup(0);

        // Setup
        uint amountIn = 1 ether;
        token.mint(address(this), amountIn);
        token.approve(address(factory), amountIn);

        // Record initial balances
        uint buyerTokenBalanceBefore = token.balanceOf(address(this));
        uint buyerIssuanceBalanceBefore = issuanceToken.balanceOf(address(this));
        uint purchaseReturn = fundingManager.calculatePurchaseReturn(amountIn);

        // Execute buy
        factory.buyFor(
            address(fundingManager), address(this), amountIn, purchaseReturn
        );

        // Verify balance changes
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

        // Verify curve state
        assertTrue(fundingManager.buyIsOpen(), "Buying should be open");
        assertTrue(fundingManager.sellIsOpen(), "Selling should be open");
        assertFalse(
            factory.getIsGraduated(address(fundingManager)),
            "Factory should not be graduated"
        );
    }

    /// @notice Tests complete sell operation of previously purchased tokens
    /// @dev Verifies:
    ///      - Purchase success
    ///      - Sale execution
    ///      - Final balance check
    function test_sellTo() public {
        _setupMigrationConfig(true);

        // Post setup
        (
            ,
            ERC20Issuance_v1 issuanceToken,
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager
        ) = postSetup(0);

        // First buy tokens
        uint amountIn = 1 ether;
        token.mint(address(this), amountIn);
        token.approve(address(factory), amountIn);
        uint purchaseReturn = fundingManager.calculatePurchaseReturn(amountIn);
        factory.buyFor(
            address(fundingManager), address(this), amountIn, purchaseReturn
        );

        // Verify purchase
        uint issuanceBalanceBeforeSale = issuanceToken.balanceOf(address(this));
        assertGt(
            issuanceBalanceBeforeSale, 0, "Buyer should have issuance tokens"
        );

        // Sell tokens
        issuanceToken.approve(address(factory), issuanceBalanceBeforeSale);
        uint saleReturn =
            fundingManager.calculateSaleReturn(issuanceBalanceBeforeSale);
        factory.sellTo(
            address(fundingManager),
            address(this),
            issuanceBalanceBeforeSale,
            saleReturn
        );

        // Verify sale
        uint issuanceBalanceAfterSale = issuanceToken.balanceOf(address(this));
        assertEq(
            issuanceBalanceAfterSale,
            0,
            "Buyer should have no issuance tokens after sale"
        );
    }

    // =========================================================================
    // Test Cases: Migration Scenarios
    // =========================================================================

    /// @notice Tests buying tokens that trigger migration threshold
    /// @dev Verifies:
    ///      - Migration trigger conditions
    ///      - Post-migration curve state
    ///      - Token refunds and balances
    ///      - Ownership transitions
    function test_buyForUpTo_AtAboveThreshold() public {
        _setupMigrationConfig(true);

        // Post setup
        (
            IOrchestrator_v1 orchestrator,
            ERC20Issuance_v1 issuanceToken,
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager
        ) = postSetup(0);

        // Fee Rates
        uint protocolFeeRate = feeManager.getDefaultCollateralFee();

        // Setup purchase
        uint amountIn = 12 ether;
        token.mint(address(this), amountIn);
        token.approve(address(factory), amountIn);

        // First purchase (half)
        uint firstPurchaseReturn =
            fundingManager.calculatePurchaseReturn(amountIn / 2);
        factory.buyFor(
            address(fundingManager),
            address(this),
            amountIn / 2,
            firstPurchaseReturn
        );

        // Withdraw fees to staking
        factory.withdrawAllProjectCollateralFeesToStaking();

        // Second purchase (half) - triggers migration
        uint secondPurchaseReturn =
            fundingManager.calculatePurchaseReturn(amountIn / 2);
        factory.buyFor(
            address(fundingManager),
            address(this),
            amountIn / 2,
            secondPurchaseReturn
        );

        // Verify curve state after migration
        assertFalse(fundingManager.buyIsOpen(), "Buying should be closed");
        assertFalse(fundingManager.sellIsOpen(), "Selling should be closed");
        assertTrue(
            factory.getIsGraduated(address(fundingManager)),
            "Factory should be graduated"
        );

        // Verify refund
        uint totalAmountIn = amountIn;

        // Calculate fees on full amount
        uint protocolFees = totalAmountIn * protocolFeeRate / 10_000;
        uint pusherFee = (amountIn / 2) * 100 / 9900;

        // Calculate expected refund
        uint expectedRefund =
            totalAmountIn - protocolFees - pusherFee - migrationThreshold;
        assertApproxEqAbs(
            token.balanceOf(address(this)),
            expectedRefund,
            0.02 ether,
            "Buyer should be reimbursed excess payment"
        );

        // Verify token balances
        assertGt(
            issuanceToken.balanceOf(address(this)),
            0,
            "Buyer should have issuance tokens"
        );
        assertEq(
            token.balanceOf(address(fundingManager)),
            0,
            "Funding manager should have no collateral after migration"
        );

        // Verify ownership based on migration type
        assertEq(
            issuanceToken.owner(),
            address(0),
            "Issuance token should be renounced upon migration"
        );
        if (migrationConfig.isImmutable) {
            assertFalse(
                orchestrator.authorizer().hasRole(
                    orchestrator.authorizer().getAdminRole(), workflowAdmin
                ),
                "Admin should not have admin rights (immutable)"
            );
        } else {
            assertTrue(
                orchestrator.authorizer().hasRole(
                    orchestrator.authorizer().getAdminRole(), workflowAdmin
                ),
                "Admin should have admin rights (mutable)"
            );
        }
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    /// @notice Deploys and configures a new workflow instance
    /// @param initialPurchaseAmount Amount of tokens to purchase during setup
    /// @return orchestrator The deployed orchestrator contract
    /// @return issuanceToken The deployed issuance token contract
    /// @return fundingManager The deployed funding manager contract
    function postSetup(uint initialPurchaseAmount)
        internal
        returns (
            IOrchestrator_v1 orchestrator,
            ERC20Issuance_v1 issuanceToken,
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager
        )
    {
        // Deploy workflow and record events
        vm.recordLogs();
        orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount,
            migrationConfig
        );

        // Extract issuance token address from events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (, bytes32 eventTopic) = eventHelpers.getEventTopic(
            IMigrating_PIM_Factory_v1.PIMWorkflowCreated.selector, logs, 2
        );

        address issuanceTokenAddress =
            eventHelpers.getAddressFromTopic(eventTopic);

        // Initialize contract references
        issuanceToken = ERC20Issuance_v1(issuanceTokenAddress);
        fundingManager = FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );
    }

    // Configuration helpers
    function _setupWorkflowConfig() internal {
        workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });
    }

    function _setupModuleConfigs() internal {
        // Authorizer
        setUpRoleAuthorizer();
        authorizerConfig = IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(address(workflowAdmin))
        );

        // Payment Processor
        setUpSimplePaymentProcessor();
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
        );

        // Payment Router
        setUpPaymentRouter();
        logicModuleConfigs.push(
            IOrchestratorFactory_v1.ModuleConfig(
                paymentRouterMetadata, bytes("")
            )
        );

        // Staking Manager
        setUpLM_PC_Staking_v1();
    }

    function _setupBondingCurveConfig() internal {
        // Funding Manager: Restricted Bancor Virtual Supply
        setUpBancorVirtualSupplyBondingCurveFundingManager();
        bcProperties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
            .BondingCurveProperties({
            formula: address(formula),
            reserveRatioForBuying: reserveRatio,
            reserveRatioForSelling: reserveRatio,
            buyFee: 100,
            sellFee: 100,
            buyIsOpen: true,
            sellIsOpen: true,
            initialIssuanceSupply: initialIssuuanceSupply,
            initialCollateralSupply: initialCollateralSupply
        });

        fundingManagerConfig = IOrchestratorFactory_v1.ModuleConfig(
            restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata,
            abi.encode(address(0), bcProperties, token)
        );

        // Issuance token parameters
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: 1_000_000_000e18
        });
    }

    function _setupMigrationConfig(bool isImmutable) internal {
        migrationConfig = IMigrating_PIM_Factory_v1.MigrationConfig({
            isImmutable: isImmutable,
            migrationThreshold: migrationThreshold,
            dexAdapter: uniswapAdapter,
            lpTokenRecipient: address(0)
        });
    }

    /// @notice Deploys Uniswap infrastructure for testing
    function deployUniswapAdapter() internal returns (address) {
        vm.etch(uniswapFactoryAddress, uniswapV2FactoryBytecode);
        vm.etch(uniswapRouterAddress, uniswapV2Router02Bytecode);
        return address(
            new UniswapV2Adapter(uniswapFactoryAddress, uniswapRouterAddress)
        );
    }
}
