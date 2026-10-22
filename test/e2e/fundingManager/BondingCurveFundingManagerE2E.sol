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

// SuT
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from
    "test/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

contract BondingCurveFundingManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    ERC20Issuance_v1 issuanceToken;

    address alice = address(0xA11CE);
    uint aliceBuyAmount = 200_000e18;

    address bob = address(0x606);
    uint bobBuyAmount = 5000e18;

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

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
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

        // Additional Logic Modules
        setUpBountyManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bountyManagerMetadata, bytes("")
            )
        );
    }

    function test_e2e_OrchestratorFundManagement() public {
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

        // Mint some tokens to alice and bob in order to fund the fundingmanager.

        // Alice will perform a very big initial buy.
        token.mint(alice, aliceBuyAmount);
        token.mint(bob, bobBuyAmount);
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
            assertTrue(issuanceToken.balanceOf(bob) > 0);
        }
        vm.stopPrank();

        // If the orchestrator spends half of the deposited tokens in the fundingmanager, i.e. for a logic module,
        // alice and bob are still able to withdraw their respective leftover
        // of the tokens.
        // Note that we simulate orchestrator spending by just burning tokens.
        /*uint halfOfDeposit = token.balanceOf(address(fundingManager)) / 2;
        fundingManager.setVirtualCollateralSupply(halfOfDeposit);*/

        buf_minAmountOut =
            fundingManager.calculateSaleReturn(issuanceToken.balanceOf(bob));

        // Bob is also able to withdraw half of his funded tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to fundingmanager.
            issuanceToken.approve(
                address(fundingManager), issuanceToken.balanceOf(bob)
            );

            fundingManager.sell(issuanceToken.balanceOf(bob), buf_minAmountOut);
            assertApproxEqRel(token.balanceOf(bob), bobBuyAmount, 0.00001e18); // ensures that the imprecision introduced by the math stays below 0.001%
        }
        vm.stopPrank();

        // Alice is now able to withdraw half her funded tokens.
        buf_minAmountOut =
            fundingManager.calculateSaleReturn(issuanceToken.balanceOf(alice));

        vm.startPrank(alice);
        {
            // Approve tokens to fundingmanager.
            issuanceToken.approve(
                address(fundingManager), issuanceToken.balanceOf(alice)
            );

            fundingManager.sell(
                issuanceToken.balanceOf(alice), buf_minAmountOut
            );
            assertApproxEqRel(
                token.balanceOf(alice), aliceBuyAmount, 0.00001e18
            ); // ensures that the imprecision introduced by the math stays below 0.001%
        }
        vm.stopPrank();

        // After redeeming all their fundingmanager function tokens, the tokens got
        // burned.
        // Half of the deposited funds (the ones we set to "ignore" by modifying the virtual supply) are still in the manager
        assertEq(issuanceToken.balanceOf(alice), 0);
        assertEq(issuanceToken.balanceOf(bob), 0);
        assertApproxEqAbs(
            token.balanceOf(address(fundingManager)), 0, 0.00001e18
        );
    }
}
