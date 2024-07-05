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

    function test_BancorFormula_WithExplanations() public {
        // VARIABLES

        uint NUM_OF_ROUNDS = 3;

        uint SUPPLY_BASE = 1000; // Absolute value
        uint BALANCE_BASE = 100; // Absolute value

        uint32 RESERVE_RATIO = 100_000; // In PPM

        uint depositAmount = 100e18;

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

            uint receivedAmount = bancorFormula.calculatePurchaseReturn(
                SUPPLY_BASE, BALANCE_BASE, RESERVE_RATIO, depositAmount
            );

            console.log("Received Amount after a deposit: ");
            console.log("\t\t\t\t", receivedAmount);
            console.log("---------------------------------");
            console.log("\n");

            console.log("With \"normal\" supply numbers:");
            console.log("---------------------------------");
            console.log("\tSupply: \t\t", SUPPLY_BASE * 1e18);
            console.log("\tBalance: \t\t ", BALANCE_BASE * 1e18);
            console.log("\n");
            console.log("\tDeposit Amount: \t", depositAmount);

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

            receivedAmount = bancorFormula.calculatePurchaseReturn(
                SUPPLY_BASE * 1e32,
                BALANCE_BASE * 1e32,
                RESERVE_RATIO,
                depositAmount
            );

            console.log("Received Amount after a deposit : ");
            console.log("\t\t\t\t", receivedAmount);
            console.log("---------------------------------");
            console.log("\n");

            SUPPLY_BASE *= 2;
            BALANCE_BASE *= 2;
        }
    }
}
