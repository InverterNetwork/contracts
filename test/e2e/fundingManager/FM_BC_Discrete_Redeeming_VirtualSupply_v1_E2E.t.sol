// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

import {DiscreteCurveMathLibV1_Exposed} from
    "@mocks/modules/fundingManager/bondingCurve/DiscreteCurveMathLibV1_Exposed.sol";
import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {
    DiscreteCurveMathLib_v1,
    PackedSegmentLib
} from
    "src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// SuT
import {
    FM_BC_Discrete_Redeeming_VirtualSupply_v1,
    IFM_BC_Discrete_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IFM_EXT_TokenVault_v1} from
    "@fm/extensions/interfaces/IFM_EXT_TokenVault_v1.sol";

contract FM_BC_Discrete_Redeeming_VirtualSupply_v1_E2E is E2ETest {
    using PackedSegmentLib for PackedSegment;

    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    ERC20Issuance_v1 issuanceToken;

    DiscreteCurveMathLibV1_Exposed internal exposedLib;

    address rebalanceTreasury = makeAddr("rebalanceTreasury");

    address alice = address(0xA11CE);
    address bob = address(0x606);
    address trader = address(0xBEEF);

    // Based on flatSlopedTestCurve initialized in setUp():
    //
    //     Price (ether)
    //       ^
    //     0.82|                     +------+ (Supply: 100)
    //         |                     |      |
    //     1.04|             +-------+      | (Supply: 75)
    //         |             |              |
    //         |             |              |
    //         |             |              |
    //         |             |              |
    //     1.00|-------------+              | (Supply: 1_000_000)
    //         +-------------+--------------+--> Supply (ether)
    //         0             1e6     1.04e6  1.08e6
    //
    //          Step Prices:
    //          Supply  0-50:  Price 0.50 (Segment 0, Step 0)
    //          Supply 50-75:  Price 0.80 (Segment 1, Step 0)
    //          Supply 75-100: Price 0.82 (Segment 1, Step 1)
    PackedSegment[] internal flatSlopedTestCurve;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        exposedLib = new DiscreteCurveMathLibV1_Exposed();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpFM_BC_Discrete_Redeeming_VirtualSupply_v1();

        // Floor Values
        uint floorPrice = 1e6; //1 Dollar
        uint floorSupply = 1_000_000 ether; // 1 Million Floor Tokens

        // Curve Values
        uint initialPrice = 1.4e6; //1.4 Dollar
        uint priceIncrease = 0.4e6; //0.4 Dollar
        uint supplyPerStep = 40_000 ether; //40.000 Floor Tokens
        uint numberOfSteps = type(uint16).max; //65535 Steps (max value)

        // --- Initialize flatSlopedTestCurve ---
        flatSlopedTestCurve = new PackedSegment[](2);

        // Floor Segment
        flatSlopedTestCurve[0] = exposedLib.exposed_createSegment(
            floorPrice, //initialPriceOfSegment
            0, //priceIncreasePerStep (We have only one step)
            floorSupply, //supplyPerStep
            1 //numberOfSteps (1 equals one vertical element)
        );

        // Discrete Curve Segment
        flatSlopedTestCurve[1] = exposedLib.exposed_createSegment(
            initialPrice, //initialPriceOfSegment
            priceIncrease, //priceIncreasePerStep
            supplyPerStep, //supplyPerStep
            numberOfSteps //numberOfSteps
        );

        issuanceToken =
            new ERC20Issuance_v1("Floor Token", "FT", 18, type(uint).max - 1);
        issuanceToken.setMinter(address(this), true);

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                FM_BC_Discrete_Redeeming_VirtualSupply_v1_Metadata,
                abi.encode(address(issuanceToken), token, flatSlopedTestCurve)
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

    function test_e2e_OrchestratorFundManagement_CurveAdaptions() public {
        //--------------------------------------------------------------------------------
        // Setup

        // Warp time to account for time calculations
        vm.warp(52 weeks);

        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_BC_Discrete_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Discrete_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        // Update protocol fee cache
        // Turned off for now to make calculations easier
        //fundingManager.updateProtocolFeeCache();

        issuanceToken.setMinter(address(fundingManager), true);

        //--------------------------------------------------------------------------------
        // Adapted Curve Values Version 1

        exposedLib = new DiscreteCurveMathLibV1_Exposed();

        // Floor Values
        uint floorPrice = 8e5; //0.8 Dollar
        uint floorSupply = 1_250_000 ether; // 1.25 Million Floor Tokens

        // Curve Values
        uint initialPrice = 1.6e6; //1.6 Dollar
        uint priceIncrease = 0.4e6; //0.8 Dollar
        uint supplyPerStep = 80_000 ether; //80.000 Floor Tokens
        uint numberOfSteps = type(uint16).max; //65535 Steps (max value)

        // --- Initialize newCurve ---
        PackedSegment[] memory newCurve = new PackedSegment[](2);

        // Floor Segment
        newCurve[0] = exposedLib.exposed_createSegment(
            floorPrice, //initialPriceOfSegment
            0, //priceIncreasePerStep (We have only one step)
            floorSupply, //supplyPerStep
            1 //numberOfSteps (1 equals one vertical element)
        );

        // Discrete Curve Segment
        newCurve[1] = exposedLib.exposed_createSegment(
            initialPrice, //initialPriceOfSegment
            priceIncrease, //priceIncreasePerStep
            supplyPerStep, //supplyPerStep
            numberOfSteps //numberOfSteps
        );

        // Check that new Values work
        fundingManager.reconfigureSegments(newCurve);
    }

    function test_e2e_OrchestratorFundManagement_BasicFunctionalities()
        public
    {
        //--------------------------------------------------------------------------------
        // Setup

        // Warp time to account for time calculations
        vm.warp(52 weeks);

        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_BC_Discrete_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Discrete_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        // Update protocol fee cache
        // Turned off for now to make calculations easier
        //fundingManager.updateProtocolFeeCache();

        issuanceToken.setMinter(address(fundingManager), true);

        //--------------------------------------------------------------------------------
        // Setup

        uint aliceBuyAmount = 500_000e6;
        uint bobBuyAmount = 500_000e6;

        // Mint tokens to participants
        token.mint(alice, aliceBuyAmount);
        token.mint(bob, bobBuyAmount);

        // --------------------------------------------------------------------------------
        // Simulate Initial Buy of the Floor

        // Set Fees to 0
        fundingManager.setBuyFee(0);

        // Open up Curve
        fundingManager.openBuy();
        fundingManager.openSell();

        // Buy Floor Tokens Alice
        vm.startPrank(alice);
        token.approve(address(fundingManager), aliceBuyAmount);
        fundingManager.buy(aliceBuyAmount, 1);
        vm.stopPrank();

        // Check Alice's Balance
        assertEq(
            issuanceToken.balanceOf(alice),
            aliceBuyAmount / 1e6 * 1 ether // 1 Dollar Should buy 1 Ether of Floor Tokens
        );

        // Buy Floor Tokens Bob
        vm.startPrank(bob);
        token.approve(address(fundingManager), bobBuyAmount);
        fundingManager.buy(bobBuyAmount, 1);
        vm.stopPrank();

        // Check Bob's Balance
        assertEq(
            issuanceToken.balanceOf(bob),
            bobBuyAmount / 1e6 * 1 ether // 1 Dollar Should buy 1 Ether of Floor Tokens
        );

        // Set Fees back to original value
        fundingManager.setBuyFee(100); //1% Fees

        // --------------------------------------------------------------------------------
        // Simulate Buy and Sell Actions after Floor is bought

        uint traderSizes = 1000e6; // 1000 Dollar per Trade
        uint tradesPerTimeUnit = 1000; // trades per Week

        uint tradeVolume = traderSizes * tradesPerTimeUnit;

        // Give Trader some tokens
        token.mint(trader, tradeVolume);

        // Trader Buys
        vm.startPrank(trader);
        token.approve(address(fundingManager), tradeVolume);
        fundingManager.buy(tradeVolume, 1);
        // Trader Sells
        fundingManager.sell(issuanceToken.balanceOf(trader), 1);
        vm.stopPrank();

        // Remove collected fees to rebalance treasury
        // Fee Collected can be looked up via the ProjectCollateralFeeWithdrawn event
        fundingManager.withdrawProjectCollateralFee(
            rebalanceTreasury, fundingManager.projectCollateralFeeCollected()
        );

        // Relocation with outside Liquidity
        // Add to rebalance treasury until it has 200_000 tokens
        token.mint(
            rebalanceTreasury, 200_000e6 - token.balanceOf(rebalanceTreasury)
        );

        uint injectionAmount = token.balanceOf(rebalanceTreasury);
        uint virtualCollateralSupply =
            fundingManager.getVirtualCollateralSupply();

        // Move funds to fundingManager
        vm.startPrank(rebalanceTreasury);
        token.approve(address(fundingManager), injectionAmount);
        token.transfer(address(fundingManager), injectionAmount);
        vm.stopPrank();

        // Update the virtual collateral balance
        fundingManager.setVirtualCollateralSupply(
            injectionAmount + virtualCollateralSupply
        );

        // Define new curve

        // Floor Values
        uint floorPrice = 1.2e6; //1,1 Dollar
        uint floorSupply = 1_000_000 ether; // 1 Million Floor Tokens
        // uint floorValue = floorPrice * floorSupply / 1 ether; // Should be around 1_155_000 Dollar

        // Curve Values
        uint initialPrice = 1.5e6; //1.4 Dollar
        uint priceIncrease = 0.4e6; //0.4 Dollar
        uint supplyPerStep = 40_000 ether; //40.000 Floor Tokens
        uint numberOfSteps = type(uint16).max; //65535 Steps (max value)

        // Configute new Curve
        PackedSegment[] memory newCurve = new PackedSegment[](2);

        // Floor Segment
        newCurve[0] = exposedLib.exposed_createSegment(
            floorPrice, //initialPriceOfSegment
            0, //priceIncreasePerStep (We have only one step)
            floorSupply, //supplyPerStep
            1 //numberOfSteps (1 equals one vertical element)
        );

        // Discrete Curve Segment
        newCurve[1] = exposedLib.exposed_createSegment(
            initialPrice, //initialPriceOfSegment
            priceIncrease, //priceIncreasePerStep
            supplyPerStep, //supplyPerStep
            numberOfSteps //numberOfSteps
        );

        fundingManager.reconfigureSegments(newCurve);
    }
}
