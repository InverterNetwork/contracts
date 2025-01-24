// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// SuT
import {
    FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1,
    IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1,
    IFM_BC_BondingSurface_Redeeming_v1
} from
    "@fm/bondingCurve/FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IFM_EXT_TokenVault_v1} from
    "@fm/extensions/interfaces/IFM_EXT_TokenVault_v1.sol";

contract BondingSurfaceFundingManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    ERC20Issuance_v1 issuanceToken;

    address alice = address(0xA11CE);

    address bob = address(0x606);

    address riskManager = makeAddr("RISK_MANAGER");
    address coverManager = makeAddr("COVER_MANAGER");
    address curveUser = makeAddr("CURVE_USER");

    address liquidityVaultController = makeAddr("liquidityVaultController");

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpBondingSurfaceRedeemingRestrictedRepayerSeizable();

        // BancorFormula 'formula' is instantiated in the E2EModuleRegistry

        issuanceToken = new ERC20Issuance_v1(
            "Bonding Surface Token",
            "BST",
            18,
            type(uint).max - 1,
            address(this)
        );

        IFM_BC_BondingSurface_Redeeming_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_BondingSurface_Redeeming_v1
                .BondingCurveProperties({
                formula: address(bondingSurface),
                capitalRequired: 1_000_000 * 1e18, // Taken from Topos repo test case
                basePriceMultiplier: 0.000001 ether,
                // Set pAMM properties
                buyIsOpen: true,
                sellIsOpen: true,
                buyFee: 100,
                sellFee: 100
            });

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bondingSurfaceRedeemingRestrictedRepayerSeizableMetadata,
                abi.encode(
                    address(issuanceToken),
                    token,
                    bc_properties,
                    liquidityVaultController,
                    100,
                    false
                )
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata, bytes("")
            )
        );

        // Additional Logic Modules
        setUpPaymentRouter();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                paymentRouterMetadata, bytes("")
            )
        );

        // TokenVault
        setUpTokenVaultFundingManagerExtension();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                tokenVaultFundingManagerExtensionMetadata, bytes("")
            )
        );
    }

    function test_e2e_OrchestratorFundManagement() public {
        //--------------------------------------------------------------------------------
        // Setup

        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
            fundingManager =
            FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1(
                address(orchestrator.fundingManager())
            );

        //get token vault address from orchestrator
        address tokenVault;
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(IFM_EXT_TokenVault_v1).interfaceId
                )
            ) {
                tokenVault = modulesList[i];
                break;
            }
        }

        issuanceToken.setMinter(address(fundingManager), true);

        // Make sure fundingManager contains MinimalReserve

        token.mint(address(fundingManager), fundingManager.MIN_RESERVE());

        // Set TokenVault
        fundingManager.setTokenVault(address(tokenVault));

        //--------------------------------------------------------------------------------
        // Setup

        uint aliceBuyAmount = 2_000_000e18;
        uint bobBuyAmount = 5_000_000e18;

        // Mint tokens to alice and bob
        token.mint(alice, aliceBuyAmount);
        token.mint(bob, bobBuyAmount);

        //--------------------------------------------------------------------------------
        // Buy and Sell

        // Mint some tokens to alice and bob in order to fund the fundingmanager.

        uint buf_minAmountOut =
            fundingManager.calculatePurchaseReturn(aliceBuyAmount); // buffer variable to store the minimum amount out on calls to the buy and sell functions

        vm.startPrank(alice);
        {
            // Approve tokens to orchestrator.
            token.approve(address(fundingManager), aliceBuyAmount);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.buy(aliceBuyAmount, buf_minAmountOut);

            // After the deposit, alice received some amount of receipt tokens
            // from the fundingmanager.
            assertTrue(issuanceToken.balanceOf(alice) > 0);
        }
        vm.stopPrank();
        buf_minAmountOut = fundingManager.calculatePurchaseReturn(bobBuyAmount);

        // Bob performs a buy
        vm.startPrank(bob);
        {
            // Approve tokens to fundingmanager.
            token.approve(address(fundingManager), bobBuyAmount);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.buy(bobBuyAmount, buf_minAmountOut);

            // After the deposit, bob received some amount of receipt tokens
            // from the fundingmanager.
            assertEq(issuanceToken.balanceOf(bob), buf_minAmountOut);
        }
        vm.stopPrank();

        // If the orchestrator spends quarter of the deposited tokens in the fundingmanager, i.e. for a logic module,
        // alice and bob are still able to withdraw their respective leftover
        // of the tokens.
        // Note that we simulate orchestrator spending by just burning tokens.
        uint quarterOfDeposit = token.balanceOf(address(fundingManager)) / 4;
        token.burn(address(fundingManager), quarterOfDeposit);

        buf_minAmountOut =
            fundingManager.calculateSaleReturn(issuanceToken.balanceOf(bob));

        // Bob is also able to withdraw his funded tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to fundingmanager.
            issuanceToken.approve(
                address(fundingManager), issuanceToken.balanceOf(bob)
            );

            fundingManager.sell(issuanceToken.balanceOf(bob), buf_minAmountOut);
            assertEq(token.balanceOf(bob), buf_minAmountOut);
        }
        vm.stopPrank();

        // Alice is now able to withdraw
        // She can do that until the min reserve limit that was set
        buf_minAmountOut = fundingManager.calculateSaleReturn(
            issuanceToken.balanceOf(alice) / 2
        );
        emit here();

        vm.startPrank(alice);
        {
            fundingManager.sell(
                issuanceToken.balanceOf(alice) / 2, buf_minAmountOut
            );
            assertEq(token.balanceOf(alice), buf_minAmountOut);
        }
        vm.stopPrank();
    }

    event here();
}
