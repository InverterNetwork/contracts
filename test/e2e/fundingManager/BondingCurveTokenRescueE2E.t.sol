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
import {LM_PC_PaymentRouter_v1} from "@lm/LM_PC_PaymentRouter_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
// SuT
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from
    "test/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

contract BondingCurveTokenRescueE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    ERC20Issuance_v1 issuanceToken;

    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
        bc_properties;

    address alice = address(0xA11CE);
    uint aliceBuyAmount = 200_000e18;

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
        setUpBancorVirtualSupplyBondingCurveFundingManager();

        // BancorFormula 'formula' is instantiated in the E2EModuleRegistry

        issuanceToken = new ERC20Issuance_v1(
            "Bonding Curve Token", "BCT", 18, type(uint).max - 1, address(this)
        );

        bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
            .BondingCurveProperties({
            formula: address(formula),
            reserveRatioForBuying: 333_333,
            reserveRatioForSelling: 333_333,
            buyFee: 0,
            sellFee: 0,
            buyIsOpen: true,
            sellIsOpen: true,
            initialIssuanceSupply: 10,
            initialCollateralSupply: 30
        });

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(address(issuanceToken), bc_properties, token)
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
    }

    function test_e2e_TokenRescue() public {
        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        issuanceToken.setMinter(address(fundingManager), true);

        // Mint some tokens to alice in order to fund the fundingmanager.

        // Alice will perform a very big initial buy.
        token.mint(alice, aliceBuyAmount);
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

        // --------------------------------------------------------------------------------
        // Start Token Rescue

        //Pause Buy and Sell functionality
        fundingManager.closeBuy();
        fundingManager.closeSell();

        // Stop minting of new tokens

        issuanceToken.setMinter(address(fundingManager), false);

        // Get the old BC Parameters and put in initial Collateral Supply correctly

        uint oldIssuanceSupply = fundingManager.getVirtualIssuanceSupply();
        uint oldCollateralSupply = fundingManager.getVirtualCollateralSupply();

        bc_properties.initialIssuanceSupply = oldIssuanceSupply;
        bc_properties.initialCollateralSupply = oldCollateralSupply;

        // Deploy new FM_BC with old Parameters, but dont link it to workflow yet

        address newBondingCurve = moduleFactory.createAndInitModule(
            bancorVirtualSupplyBondingCurveFundingManagerMetadata,
            orchestrator,
            abi.encode(address(issuanceToken), bc_properties, address(token)),
            workflowConfig
        );

        // Create PaymentRouter
        setUpPaymentRouter();

        address paymentRouter = moduleFactory.createAndInitModule(
            paymentRouterMetadata, orchestrator, bytes(""), workflowConfig
        );

        // Add PaymentRouter to Orchestrator

        orchestrator.initiateAddModuleWithTimelock(paymentRouter);
        // wait for timelock to expire
        vm.warp(block.timestamp + 1 weeks);

        orchestrator.executeAddModule(paymentRouter);

        // Transfer all collateral to the new BC

        LM_PC_PaymentRouter_v1(paymentRouter).grantModuleRole(
            LM_PC_PaymentRouter_v1(paymentRouter).PAYMENT_PUSHER_ROLE(),
            address(this)
        );

        LM_PC_PaymentRouter_v1(paymentRouter).pushPayment(
            newBondingCurve, // recipient
            address(token), // token
            // This represented the allowed amount of collateral token to be transferred
            token.balanceOf(address(fundingManager))
                - fundingManager.projectCollateralFeeCollected(), // amount
            block.timestamp, // startTime
            0, // cliff
            block.timestamp // endTime
        );

        // Initiate setting of new Funding Manager
        orchestrator.initiateSetFundingManagerWithTimelock(
            IFundingManager_v1(newBondingCurve)
        );

        // wait for timelock to expire
        vm.warp(block.timestamp + 1 weeks);

        orchestrator.executeSetFundingManager(
            IFundingManager_v1(newBondingCurve)
        );

        // Enable Minting again for new BC

        issuanceToken.setMinter(newBondingCurve, true);

        // Open Buy and Sell functionality again
        fundingManager.openBuy();
        fundingManager.openSell();

        // Check if everything is setup correctly

        assertEq(address(orchestrator.fundingManager()), newBondingCurve);

        fundingManager =
            FM_BC_Bancor_Redeeming_VirtualSupply_v1(newBondingCurve);

        assertEq(oldIssuanceSupply, fundingManager.getVirtualIssuanceSupply());
        assertEq(
            oldCollateralSupply, fundingManager.getVirtualCollateralSupply()
        );

        // Bob performs a buy
        address bob = address(0x606);
        uint bobBuyAmount = 5000e18;
        token.mint(bob, bobBuyAmount);
        buf_minAmountOut = fundingManager.calculatePurchaseReturn(bobBuyAmount);

        vm.startPrank(bob);
        {
            // Approve tokens to fundingmanager.
            token.approve(address(fundingManager), bobBuyAmount);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.buy(bobBuyAmount, buf_minAmountOut);

            // After the deposit, bob received some amount of receipt tokens
            // from the fundingmanager.
            assertTrue(issuanceToken.balanceOf(bob) > 0);
        }
        vm.stopPrank();
    }
}
