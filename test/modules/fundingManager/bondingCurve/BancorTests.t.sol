// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";

contract BancorTests is Test {
    address formula;
    BancorFormula bancorFormula;

    function setUp() public virtual {
        bancorFormula = new BancorFormula();
        formula = address(bancorFormula);
    }

    function _helper_getSupplyForGivenReserveAtSpotPrice(
        uint reserve,
        uint reserveRatio,
        uint spotPrice
    ) internal pure returns (uint) {
        return (1e12 * reserve) / (reserveRatio * spotPrice);
    }

    /*
    MSG from rohan:

    Scenario 1: Financially Conservative Approach

    Reserve Ratio: Low (16%)
    Initial Reserve Requirements: $1.8M (assuming Prb current price at 11 Lira)
    Outcomes:
    Lower fee collection (Model estimate: ~ 3%, Industry Expert estimate: 8%)
    Less volatility reduction
    Moderate Growth in reserves (Model estimate ROI: ~33.42%)
    Scenario 2: Balanced Approach



    -> ReserveRatio: 160_000
    -> initialReserve: 1_800_000e18
    -> spotPrice: 11e18

    Reserve Ratio: Medium (25%)
    Initial Reserve Requirements: $2.4M
    Outcomes:
    Optimal fee collection (Model estimate: ~ 3.7%, Industry Expert estimate: 12%)
    Moderate volatility reduction
    Higher Growth in reserves (Model estimate: ~38)
    Scenario 3: Financially Aggressive Approach

    -> ReserveRatio: 250_000
    -> initialReserve: 2_400_000e18
    -> spotPrice: 11e18


    Reserve Ratio: High (35%)
    Initial Reserve Requirements: $3.7 M
    Outcomes:
    Fee collection (Model estimate: ~ 4%, Industry Expert estimate: 15%)
    Optimal volatility reduction
    Highest potential reserve +fees growth (Model estimate ROI: 44.9%)

    -> ReserveRatio: 250_000
    -> initialReserve: 2_400_000e18
    -> spotPrice: 11e18




    */

    function test_logRohanParams() public view {
        console.log("=================================");
        console.log("Scenario 1: Financially Conservative Approach");

        uint32 RESERVE_RATIO = 160_000; // In PPM
        uint INITIAL_RESERVE = 1_800_000e18;
        uint SPOT_PRICE = 11e6; // relationship in PPM; 1:1 = 1_000_000
        uint INITIAL_SUPPLY = _helper_getSupplyForGivenReserveAtSpotPrice(
            INITIAL_RESERVE, RESERVE_RATIO, SPOT_PRICE
        );

        console.log("=================================");
        console.log("Reserve Ratio: %s", RESERVE_RATIO);
        console.log("Initial Reserve Requirements: %s", INITIAL_RESERVE);
        console.log("Initial Supply: %s", INITIAL_SUPPLY);
        console.log("Spot Price: %s", SPOT_PRICE);

        console.log("=================================");
        console.log("Scenario 2: Balanced Approach");
        console.log("=================================");

        RESERVE_RATIO = 250_000; // In PPM
        INITIAL_RESERVE = 2_400_000e18;
        SPOT_PRICE = 11e6;
        INITIAL_SUPPLY = _helper_getSupplyForGivenReserveAtSpotPrice(
            INITIAL_RESERVE, RESERVE_RATIO, SPOT_PRICE
        );

        console.log("Reserve Ratio: %s", RESERVE_RATIO);
        console.log("Initial Reserve Requirements: %s", INITIAL_RESERVE);
        console.log("Initial Supply: %s", INITIAL_SUPPLY);
        console.log("Spot Price: %s", SPOT_PRICE);

        console.log("=================================");
        console.log("Scenario 3: Financially Aggressive Approach");
        console.log("=================================");

        RESERVE_RATIO = 350_000; // In PPM
        INITIAL_RESERVE = 3_700_000e18;
        SPOT_PRICE = 11e6;
        INITIAL_SUPPLY = _helper_getSupplyForGivenReserveAtSpotPrice(
            INITIAL_RESERVE, RESERVE_RATIO, SPOT_PRICE
        );

        console.log("Reserve Ratio: %s", RESERVE_RATIO);
        console.log("Initial Reserve Requirements: %s", INITIAL_RESERVE);
        console.log("Initial Supply: %s", INITIAL_SUPPLY);
        console.log("Spot Price: %s", SPOT_PRICE);
    }

    // ===========================================
    // ==            TEC PARAMETERS             ==
    // ===========================================
    uint32 TEC_RESERVE_RATIO = 199_800; // In PPM
    uint TEC_INITIAL_SUPPLY = 195_642_169e16;
    uint TEC_INITIAL_RESERVE = 39_097_931e16;

    uint[] reserveAmounts;

    /// @notice This test takes an initial state and performs sales to get to a poitn where the spot price is very small. It then buys back all the tokens, and verifies that the amounts received are the same as the initial ones.
    function test_BancorFormula_SellAndBuyStepByStep() public {
        uint PPM = 1_000_000;

        // TEC numbers
        uint32 RESERVE_RATIO = 199_800; // In PPM
        uint INITIAL_SUPPLY = 195_642_169e16;
        uint INITIAL_RESERVE = 39_097_931e16;

        uint test = _helper_getSupplyForGivenReserveAtSpotPrice(
            INITIAL_RESERVE, uint(RESERVE_RATIO), 1_000_200
        );
        console.log("test", test);

        // These are minimal numbers. Spot price is 0
        //uint INITIAL_SUPPLY = 56421690000000000000000;
        //uint INITIAL_RESERVE = 7662387184363186;

        // THESE ARE THE MINIMAL NUMBERS FOR THE TEC CONFIGURATION: spot price is 1, and a 1e6 buy pushes it to 0.
        // Please note that large sells can move the price below this amount. But they will need an equally big buys afterwards that pushes the balances over thsi limit again.
        //uint INITIAL_SUPPLY = 62131676819845007200000;
        //uint INITIAL_RESERVE = 12413909028605033;
        /*
        //Test
        RESERVE_RATIO = 333_333;
        INITIAL_SUPPLY = 3_000_003e18;
        INITIAL_RESERVE = 1_000_000e18;

        uint supply = INITIAL_SUPPLY;
        uint reserve = INITIAL_RESERVE;

        uint saleStepSize = 100_000e18;

        uint NUM_OF_STEPS = 0;
        //uint MAX_STEPS = 98;
        //uint[] storage reserveAmounts;
        uint curentSpotPrice = 1e12 * reserve / (supply * uint(RESERVE_RATIO));

        /*uint 1_000_000 = 1e12/RESERVE_RATIO * 1_000_000e18/x;
        x = 1e12/RESERVE_RATIO * 1_000_000e18/1_000_000;
        x = 1e12/RESERVE_RATIO * 1e18;
        x = 300000_300000000000000000*/
        /*

        // TODO: calculate the way to get the balance at a given reserve point if we have a defined curve

        console.log("Initial spot price: %s", curentSpotPrice);

        while (curentSpotPrice > 0 && NUM_OF_STEPS < 29) {
            //perform a sale

            uint receivedAmount = bancorFormula.calculateSaleReturn(
                supply, reserve, RESERVE_RATIO, saleStepSize
            );

            {
                //Logs
                console.log("=================================");
                console.log("SALE: STEP %s: ", NUM_OF_STEPS);
                console.log("=================================");

                console.log("\tSupply: \t\t", supply);
                console.log("\tReserve: \t\t ", reserve);
                console.log("\n");
                console.log("Spot Price: \t\t", curentSpotPrice);

                console.log("\tSell Amount: \t", saleStepSize);

                console.log("Received Amount after  sale: ");
                console.log("\t\t\t\t", receivedAmount);
                console.log("---------------------------------");
            }
            //update state
            NUM_OF_STEPS++;
            reserveAmounts.push(receivedAmount);
            reserve -= receivedAmount;
            supply -= saleStepSize;
            curentSpotPrice = 1e12 * reserve / (supply * uint(RESERVE_RATIO));
        }

        console.log("=================================");
        console.log("Supply after all sales: \t\t", supply);
        console.log("Reserve after all sales: \t\t ", reserve);
        uint spotPriceAfterSales =
            1e12 * reserve / (supply * uint(RESERVE_RATIO));
        console.log("Spot Price after all sales: \t\t", spotPriceAfterSales);
        console.log("=================================");

        for (uint i = 0; i < NUM_OF_STEPS; i++) {
            //buys
            uint buyAmount = reserveAmounts[reserveAmounts.length - i - 1];
            //uint buyAmount = 1e18;

            uint receivedAmount = bancorFormula.calculatePurchaseReturn(
                supply, reserve, RESERVE_RATIO, buyAmount
            );

            //if ((i + 1) == NUM_OF_STEPS) {
            //Logs
            console.log("=================================");
            console.log("BUY: STEP %s: ", i + 1);
            console.log("=================================");
            console.log("\tSupply: \t\t", supply);
            console.log("\tReserve: \t\t ", reserve);
            console.log("\n");
            uint spotPrice = 1e12 * reserve / (supply * uint(RESERVE_RATIO));
            console.log("Spot Price: \t\t", spotPrice);

            console.log("\tBuy Amount: \t", buyAmount);

            console.log("Received Amount after a deposit: ");
            console.log("\t\t\t\t", receivedAmount);
            console.log("---------------------------------");
            //}

            reserve += buyAmount;
            supply += receivedAmount;

            //assertApproxEqAbs(receivedAmount, saleStepSize, 1_000_000);
        }

        console.log("=================================");
        console.log("Supply after all buys: \t\t", supply);
        console.log("Reserve after all buys: \t\t ", reserve);
        uint spotPriceAfterBuys =
            1e12 * reserve / (supply * uint(RESERVE_RATIO));
        console.log("Spot Price after all buys: \t\t", spotPriceAfterBuys);
        console.log("=================================");
        */
    }

    function test_BancorFormula_LowBalancesThroughSale() public {
        uint PPM = 1_000_000;
        uint32 RESERVE_RATIO = 160000; // In PPM

        uint INITIAL_SUPPLY = 1022727272727272727272727;
        uint INITIAL_RESERVE = 1800000000000000000000000;

        uint fixedStaticPrice = 11000000;

        /*uint supplyCalculation =
            PPM * PPM * (66_168_439_387_169_789) / (uint(RESERVE_RATIO) * 3);

        console.log("Supply calculation: \t\t", supplyCalculation);*/

        //uint INITIAL_SUPPLY = 1e12;
        //uint INITIAL_RESERVE = 199_800;

        uint supply = INITIAL_SUPPLY;
        uint reserve = INITIAL_RESERVE;

        uint sellAmount = 900000e18;

        console.log("=================================");
        console.log("TEST SALE: ");
        console.log("=================================");

        console.log("\tSupply: \t\t", supply);
        console.log("\tReserve: \t\t ", reserve);
        console.log("\n");
        uint spotPrice = 1e12 * reserve / (supply * uint(RESERVE_RATIO));
        console.log("Spot Price: \t\t", spotPrice);
        console.log("\tSell Amount: \t", sellAmount);
        uint receivedAmount = bancorFormula.calculateSaleReturn(
            supply, reserve, RESERVE_RATIO, sellAmount
        );
        console.log("Received Amount after a sale: ");
        console.log("\t\t\t\t", receivedAmount);

        console.log(" Remaining Supply: \t", supply - sellAmount);
        console.log(" Remaining Reserve: \t", reserve - receivedAmount);

        uint newSpotPrice = 1e12 * (reserve - receivedAmount)
            / ((supply - sellAmount) * uint(RESERVE_RATIO));

        console.log("New Spot Price: \t\t", newSpotPrice);
    }

    function test_BancorFormula_StepByStep() public {
        uint PPM = 1_000_000;
        uint32 RESERVE_RATIO = 333_333; // In PPM

        //uint INITIAL_SUPPLY = 195642169e16;
        //uint INITIAL_RESERVE = 39097931e16;
        uint INITIAL_SUPPLY = 200_002_999_999_999_999_998_676;
        uint INITIAL_RESERVE = 296_306_333_665_498_798_599;

        //uint INITIAL_SUPPLY = 100003000000000000000000;
        //uint INITIAL_RESERVE = 37039881410555522331;

        uint supply = INITIAL_SUPPLY;
        uint reserve = INITIAL_RESERVE;

        uint buyPerStep = 1000e18;

        for (uint i = 0; i < 100; i++) {
            console.log("=================================");
            console.log("STEP %s: ", i + 1);
            console.log("=================================");

            console.log("\tSupply: \t\t", supply);
            console.log("\tReserve: \t\t ", reserve);
            console.log("\n");
            uint spotPrice = 1e12 * reserve / (supply * uint(RESERVE_RATIO));

            console.log("Spot Price: \t\t", spotPrice);
            console.log("\tDeposit Amount: \t", buyPerStep);
            uint receivedAmount = bancorFormula.calculatePurchaseReturn(
                supply, reserve, RESERVE_RATIO, buyPerStep
            );
            console.log("Received Amount after a deposit: ");
            console.log("\t\t\t\t", receivedAmount);

            supply += receivedAmount;
            reserve += buyPerStep;
        }
    }

    function test_BancorFormula_WithExplanations() public {
        // VARIABLES

        uint PPM = 1_000_000;

        uint NUM_OF_ROUNDS = 3;

        uint SUPPLY_BASE = 12_000_000e18; // Absolute value
        uint BALANCE_BASE = 6_600_000e18; // Absolute value

        uint32 RESERVE_RATIO = 300_000; // In PPM

        uint depositAmount = 600_000e18;

        console.log("########################################################");
        console.log("## TESTING UNEXPECTED BEHAVIOR IN THE BANCOR FORMULA ##");
        console.log("########################################################");

        console.log(
            "The Bancor formula is used to calculate the amount of tokens to be received when depositing collateral int a bonding curve, and the amount of collateral to be received when selling those tokens."
        );
        console.log(
            "In general, one would assume that when depositing a fixed amount under a given reserve ratio, the amount of tokens received should be inversely proportional to the current balance of the curve (i.e. the lower the current balance, the more tokens are minted)"
        );
        console.log("This assumption does not seem to hold.");

        console.log("=================================");
        console.log("INITIAL CONDITIONS");
        console.log("=================================");
        console.log("Reserve Ratio (in PPM): \t", RESERVE_RATIO);
        console.log("Deposit Amount per round: 100e18 tokens \t\t");

        for (uint i = 0; i < NUM_OF_ROUNDS; i++) {
            console.log("=================================");
            console.log("ROUND %s: ", i + 1);
            console.log("=================================");

            console.log("\n");
            console.log("With low supply numbers:");
            console.log("---------------------------------");
            console.log("\tSupply: \t\t", SUPPLY_BASE);
            console.log("\tBalance: \t\t ", BALANCE_BASE);
            console.log("\n");
            console.log("\tDeposit Amount: \t", depositAmount);

            uint spotPriceBuy =
                (BALANCE_BASE) / ((SUPPLY_BASE) * uint(RESERVE_RATIO));

            console.log("Spot Price for buying: \t\t", spotPriceBuy);

            uint spotPriceSell =
                (SUPPLY_BASE) / ((BALANCE_BASE) * uint(RESERVE_RATIO));

            console.log("Spot Price for selling: \t\t", spotPriceSell);

            uint receivedAmount = bancorFormula.calculatePurchaseReturn(
                SUPPLY_BASE, BALANCE_BASE, RESERVE_RATIO, depositAmount
            );

            console.log("Received Amount after a deposit: ");
            console.log("\t\t\t\t", receivedAmount);
            console.log("---------------------------------");
            console.log("\n");
            /*
            console.log("With \"normal\" supply numbers:");
            console.log("---------------------------------");
            console.log("\tSupply: \t\t", SUPPLY_BASE * 1e18);
            console.log("\tBalance: \t\t ", BALANCE_BASE * 1e18);
            console.log("\n");
            console.log("\tDeposit Amount: \t", depositAmount);

             spotPrice = uint(PPM) * uint(PPM) * BALANCE_BASE * 1e18
            / (SUPPLY_BASE * 1e18 * uint(RESERVE_RATIO));

            console.log("Spot Price: \t\t", spotPrice);

            receivedAmount = bancorFormula.calculatePurchaseReturn(
                SUPPLY_BASE * 1e18,
                BALANCE_BASE * 1e18,
                RESERVE_RATIO,
                depositAmount
            );

            console.log("Received Amount after a deposit: ");
            console.log("\t\t\t\t", receivedAmount);
            console.log("---------------------------------");
            console.log("\n");

            console.log("With high supply numbers:");
            console.log("---------------------------------");
            console.log("\tSupply: \t\t", SUPPLY_BASE * 1e32);
            console.log("\tBalance: \t\t ", BALANCE_BASE * 1e32);
            console.log("\n");
            console.log("\tDeposit Amount: \t", depositAmount);


             spotPrice = uint(PPM) * uint(PPM) * BALANCE_BASE * 1e32
            / (SUPPLY_BASE * 1e32 * uint(RESERVE_RATIO));

            console.log("Spot Price: \t\t", spotPrice);

            receivedAmount = bancorFormula.calculatePurchaseReturn(
                SUPPLY_BASE * 1e32,
                BALANCE_BASE * 1e32,
                RESERVE_RATIO,
                depositAmount
            );

            console.log("Received Amount after a deposit : ");
            console.log("\t\t\t\t", receivedAmount);
            console.log("---------------------------------");
            console.log("\n");*/

            SUPPLY_BASE *= 2;
            BALANCE_BASE *= 2;
        }
    }
}
