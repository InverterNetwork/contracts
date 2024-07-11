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

    function test_BancorFormula_suppylCalculationPlusBuys() public {
        
        uint PPM = 1_000_000;
        uint32 RESERVE_RATIO = 199_800; // In PPM

    
        // We take the reserve form the logs for the TEC case and calculate the supply
        uint INITIAL_RESERVE = 50000000000000000000000;
        uint INITIAL_SUPPLY = PPM * (INITIAL_RESERVE) / (uint(RESERVE_RATIO) );

        console.log("Reserve calculation: \t\t", INITIAL_RESERVE);
        console.log("Supply calculation: \t\t", INITIAL_SUPPLY);


        // perform a buy that should bring it up to the initial TEC state
        uint amountToBuy = 200_000e18;

        uint receivedAmount = bancorFormula.calculatePurchaseReturn(
            INITIAL_SUPPLY, INITIAL_RESERVE, RESERVE_RATIO, amountToBuy
        );

        console.log("Received Amount after a deposit: ");
        console.log("\t\t\t\t", receivedAmount);

        console.log(" Total Supply: \t", INITIAL_SUPPLY + receivedAmount);
        console.log(" Total Reserve: \t", INITIAL_RESERVE + amountToBuy);

        // check

    }

    function test_BancorFormula_LowBalancesThroughSale() public {
           uint PPM = 1_000_000;
        uint32 RESERVE_RATIO = 199_800; // In PPM

        uint INITIAL_SUPPLY = 195642169e16;
        uint INITIAL_RESERVE = 39097931e16;

        uint fixedStaticPrice = 1000220;

        uint supplyCalculation = PPM* PPM * (66168439387169789) / (uint(RESERVE_RATIO) * 3);

        console.log("Supply calculation: \t\t", supplyCalculation);

        //uint INITIAL_SUPPLY = 1e12;
        //uint INITIAL_RESERVE = 199_800;

        uint supply = INITIAL_SUPPLY;
        uint reserve = INITIAL_RESERVE;

        uint sellAmount = 1869622396000000000000000;

                console.log("=================================");
            console.log("TEST SALE: ");
            console.log("=================================");

            console.log("\tSupply: \t\t", supply);
            console.log("\tReserve: \t\t ", reserve);
            console.log("\n");
            uint spotPrice = 1e12 * reserve
            / (supply * uint(RESERVE_RATIO));
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
        uint32 RESERVE_RATIO = 199_800; // In PPM

        //uint INITIAL_SUPPLY = 195642169e16;
        //uint INITIAL_RESERVE = 39097931e16;

        uint INITIAL_SUPPLY = 1e12;
        uint INITIAL_RESERVE = 199_800;

        uint supply = INITIAL_SUPPLY;
        uint reserve = INITIAL_RESERVE;

        uint buyPerStep = 39097930999999999800200;

       for (uint i = 0; i < 10; i++) {
                    console.log("=================================");
            console.log("STEP %s: ", i + 1);
            console.log("=================================");

            console.log("\tSupply: \t\t", supply);
            console.log("\tReserve: \t\t ", reserve);
            console.log("\n");
            uint spotPrice = 1e12 * reserve
            / (supply * uint(RESERVE_RATIO));


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

            uint spotPriceBuy = (BALANCE_BASE )
            / ((SUPPLY_BASE) * uint(RESERVE_RATIO));

            console.log("Spot Price for buying: \t\t", spotPriceBuy);

            uint spotPriceSell = (SUPPLY_BASE )
            / ((BALANCE_BASE) * uint(RESERVE_RATIO));

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
