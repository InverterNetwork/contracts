// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

// OpenZeppelin
import {ERC20} from '@oz/token/ERC20/ERC20.sol';

// Test Utils
import {E2ETest} from 'test/e2e/E2ETest.sol';
import {EventHelpers} from 'test/utils/helpers/EventHelpers.sol';

// Core Interfaces
import {IOrchestrator_v1} from 'src/orchestrator/interfaces/IOrchestrator_v1.sol';
import {IOrchestratorFactory_v1} from 'src/factories/interfaces/IOrchestratorFactory_v1.sol';
import {IMigrating_PIM_Factory_v1} from 'src/factories/interfaces/IMigrating_PIM_Factory_v1.sol';

// Funding Manager Interfaces
import {IBondingCurveBase_v1} from '@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol';
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from '@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol';
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from '@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol';

// Implementations
import {ERC20Issuance_v1} from 'src/external/token/ERC20Issuance_v1.sol';
import {Migrating_PIM_Factory_v1} from 'src/factories/custom/Migrating_PIM_Factory_v1.sol';
import {IMigrating_PIM_Factory_v1} from 'src/factories/interfaces/IMigrating_PIM_Factory_v1.sol';
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from '@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol';
import {UniswapV2Adapter} from 'src/external/immutable-migration/UniswapV2Adapter.sol';

// Constants
import {uniswapV2FactoryBytecode} from 'test/lib/uniswap/uniswapV2FactoryBytecode.sol';
import {uniswapV2Router02Bytecode} from 'test/lib/uniswap/uniswapV2Router02Bytecode.sol';

address constant uniswapFactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
address constant uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

contract Migrating_PIM_Factory_v1Test is E2ETest {
    // SuT
    Migrating_PIM_Factory_v1 factory;
    address uniswapAdapter;

    // Helpers
    EventHelpers eventHelpers;

    // Deployment Parameters
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveBase_v1.IssuanceToken issuanceTokenParams;
    uint initialPurchaseAmount = 1 ether;
    uint secondaryPurchaseAmount = 10 ether;
    uint migrationThreshold = 10 ether;
    bool isImmutable = true;
    IMigrating_PIM_Factory_v1.MigrationConfig migrationConfig;

    // addresses
    address workflowAdmin = vm.addr(420);
    // address factoryDeployer = vm.addr(1);
    // address workflowDeployer = vm.addr(2);
    address mockTrustedForwarder = vm.addr(3);
    address alice = vm.addr(0xA11CE);

    // bc params
    uint initialIssuuanceSupply = 200_002_000_000_000_000_000_000;
    uint initialCollateralSupply = 296_000_000_000_000_000_000;
    uint32 reserveRatio = 160_000;

    function setUp() public override {
        super.setUp();

        uniswapAdapter = deployUniswapAdapter();

        // deploy new factory
        factory = new Migrating_PIM_Factory_v1(
            address(orchestratorFactory),
            mockTrustedForwarder
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
            roleAuthorizerMetadata,
            abi.encode(address(workflowAdmin))
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata,
            bytes('')
        );

        // Replace bounty manager setup with ImmutableMigration setup
        setUpPaymentRouter();
        logicModuleConfigs.push(
            IOrchestratorFactory_v1.ModuleConfig(
                paymentRouterMetadata,
                bytes('')
            )
        );

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

        // Put issuance token params in storage
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: 'Bonding Curve Token',
            symbol: 'BCT',
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        token.mint(address(this), initialPurchaseAmount);
        token.approve(address(factory), initialPurchaseAmount);

        // Set migration config
        migrationConfig = IMigrating_PIM_Factory_v1.MigrationConfig({
            isImmutable: isImmutable,
            migrationThreshold: migrationThreshold,
            dexAdapter: uniswapAdapter,
            lpTokenRecipient: address(0)
        });

        // Deploy workflow and set up contracts for all tests
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

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (, bytes32 eventTopic) = eventHelpers.getEventTopic(
            IMigrating_PIM_Factory_v1.PIMWorkflowCreated.selector,
            logs,
            2
        );
        address issuanceTokenAddress = eventHelpers.getAddressFromTopic(
            eventTopic
        );

        issuanceToken = ERC20Issuance_v1(issuanceTokenAddress);
        fundingManager = FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );
    }

    IOrchestrator_v1 orchestrator;
    ERC20Issuance_v1 issuanceToken;
    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager;

    function testCreatePIMWorkflow() public {
        // Check if bonding curve module has minting rights on token
        assertTrue(
            issuanceToken.allowedMinters(address(fundingManager)),
            'Bonding curve module should have minting rights on token'
        );

        // Check if issuance token is renounced (immutable) or not (mutable)
        if (isImmutable) {
            assertEq(
                issuanceToken.owner(),
                address(0),
                'Issuance token should be renounced for immutable PIM'
            );
        } else {
            assertEq(
                issuanceToken.owner(),
                workflowAdmin,
                'Issuance token should not be renounced for mutable PIM'
            );
        }

        bytes32 adminRole = orchestrator.authorizer().getAdminRole();

        assertTrue(
            orchestrator.authorizer().hasRole(adminRole, address(factory)),
            'Factory should have admin rights over workflow'
        );

        if (!isImmutable) {
            assertTrue(
                orchestrator.authorizer().hasRole(adminRole, workflowAdmin),
                'Workflow admin should have admin rights over workflow'
            );
        }

        assertGt(
            issuanceToken.balanceOf(workflowAdmin),
            0,
            'Workflow admin should have received issuance tokens'
        );

        assertEq(
            token.balanceOf(address(fundingManager)),
            initialPurchaseAmount - initialPurchaseAmount / 100, // 1% protocol fee
            'Bonding curve module should have received collateral tokens'
        );

        bytes32 curveAccess = fundingManager.CURVE_INTERACTION_ROLE();
        bytes32 curveInteractionRoleId = orchestrator
            .authorizer()
            .generateRoleId(address(fundingManager), curveAccess);
        assertTrue(
            orchestrator.authorizer().checkForRole(
                curveInteractionRoleId,
                address(factory)
            ),
            'Factory should have curve interaction role'
        );

        assertTrue(
            issuanceToken.allowedMinters(address(factory)),
            'Factory should be allowed minter'
        );
    }

    function test_buyForUpTo_BelowThreshold() public {
        // Adjust bounds to be more reasonable
        uint amountIn = 1 ether;

        // Mint collateral tokens
        token.mint(address(this), amountIn);
        // Approve factory to spend tokens
        token.approve(address(factory), amountIn);

        // Record balances before
        uint buyerTokenBalanceBefore = token.balanceOf(address(this));
        uint buyerIssuanceBalanceBefore = issuanceToken.balanceOf(
            address(this)
        );

        uint purchaseReturn = fundingManager.calculatePurchaseReturn(amountIn);

        // Execute buy
        factory.buyForUpTo(
            address(issuanceToken),
            address(this),
            amountIn,
            purchaseReturn
        );

        // Verify balances changed correctly
        assertLt(
            token.balanceOf(address(this)),
            buyerTokenBalanceBefore,
            'Token balance should decrease'
        );
        assertGt(
            issuanceToken.balanceOf(address(this)),
            buyerIssuanceBalanceBefore,
            'Issuance balance should increase'
        );

        assertTrue(fundingManager.buyIsOpen(), 'Buying should be open');
        assertTrue(fundingManager.sellIsOpen(), 'Selling should be open');

        assertFalse(factory.isGraduated(), 'Factory should not be graduated');
    }

    function test_sellTo() public {
        // First buy some tokens
        uint amountIn = 1 ether;

        token.mint(address(this), amountIn);
        token.approve(address(factory), amountIn);

        uint purchaseReturn = fundingManager.calculatePurchaseReturn(amountIn);

        factory.buyForUpTo(
            address(issuanceToken),
            address(this),
            amountIn,
            purchaseReturn
        );

        uint issuanceBalanceBeforeSale = issuanceToken.balanceOf(address(this));
        assertGt(
            issuanceBalanceBeforeSale,
            0,
            'Buyer should have received issuance tokens'
        );

        issuanceToken.approve(address(factory), issuanceBalanceBeforeSale);

        uint saleReturn = fundingManager.calculateSaleReturn(
            issuanceBalanceBeforeSale
        );

        factory.sellTo(
            address(issuanceToken),
            address(this),
            issuanceBalanceBeforeSale,
            saleReturn
        );

        uint issuanceBalanceAfterSale = issuanceToken.balanceOf(address(this));

        assertEq(
            issuanceBalanceAfterSale,
            0,
            'Buyer should not hold issuance tokens after sale'
        );
    }

    function test_buyForUpTo_AtAboveThreshold() public {
        uint amountIn = secondaryPurchaseAmount; // 10 ether, 1 ether was already purchased on inital

        token.mint(address(this), amountIn);
        token.approve(address(factory), amountIn);

        uint purchaseReturn = fundingManager.calculatePurchaseReturn(amountIn);

        factory.buyForUpTo(
            address(issuanceToken),
            address(this),
            amountIn,
            purchaseReturn
        );

        assertFalse(fundingManager.buyIsOpen(), 'Buying should be closed');
        assertFalse(fundingManager.sellIsOpen(), 'Selling should be closed');
        assertTrue(factory.isGraduated(), 'Factory should be graduated');

        // Check that only the amount up to threshold was used
        uint expectedRefund = initialPurchaseAmount +
            secondaryPurchaseAmount -
            migrationThreshold -
            fundingManager.projectCollateralFeeCollected();

        assertEq(
            token.balanceOf(address(this)),
            expectedRefund,
            'Buyer should be reimbursed the excess payment'
        );

        assertGt(
            issuanceToken.balanceOf(address(this)),
            0,
            'Buyer should receive issuance tokens'
        );

        assertEq(
            token.balanceOf(address(fundingManager)),
            fundingManager.projectCollateralFeeCollected(),
            'Funding manager should only hold the fee amount after migration'
        );
    }

    // Utils
    //--------------------------------------------------------------------------

    function deployUniswapAdapter() internal returns (address) {
        vm.etch(uniswapFactoryAddress, uniswapV2FactoryBytecode);
        vm.etch(uniswapRouterAddress, uniswapV2Router02Bytecode);

        // Deploy UniswapV2Adapter
        return
            address(
                new UniswapV2Adapter(
                    uniswapFactoryAddress,
                    uniswapRouterAddress
                )
            );
    }
}
