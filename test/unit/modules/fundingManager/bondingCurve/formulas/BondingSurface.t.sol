// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import {IQuadraticPriceFormula} from
    "src/modules/fundingManager/bondingCurve/interfaces/IQuadraticPriceFormula.sol";
import {QuadraticPriceFormula} from
    "src/modules/fundingManager/bondingCurve/formulas/QuadraticPriceFormula.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";

/* 
    @note: The comparison values in these tests have been taken from the jupyter 
        notebooks used for internal research, and are to surface possible imprecisions 
        in the unit conversion process. 
        They should not be taken as extensive testing of the formula itself.
*/

contract QuadraticPriceFormula_Test is Test {
    using FixedPointMathLib for uint;

    QuadraticPriceFormula public quadraticPriceFormula;
    uint constant BASE_MULTIPLIER = 1e11; // 10^-7 * 1e18
    uint constant WAD = 1e18;
    // 0.000001% relative tolerance for complex calculations
    uint constant REL_TOLERANCE = 1e12;

    function setUp() public {
        quadraticPriceFormula = new QuadraticPriceFormula();
    }

    function testSupportsInterface() public {
        // Test for IQuadraticPriceFormula interface support
        bytes4 interfaceId = type(IQuadraticPriceFormula).interfaceId;
        assertTrue(quadraticPriceFormula.supportsInterface(interfaceId));

        // Test for ERC165 interface support
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(quadraticPriceFormula.supportsInterface(erc165InterfaceId));

        // Test for non-supported interface
        bytes4 randomInterfaceId = 0x12345678;
        assertFalse(quadraticPriceFormula.supportsInterface(randomInterfaceId));
    }

    function testSpotPrice() public {
        // Test case 1: Ca = 10000.0, Cr = 50.0
        uint price = quadraticPriceFormula.spotPrice(
            10_000 * WAD, 50 * WAD, BASE_MULTIPLIER
        );
        assertApproxEqAbs(price, 2e17, 1e14); // 0.2 * 1e18

        // Test case 2: Ca = 50.0, Cr = 25.0
        price =
            quadraticPriceFormula.spotPrice(50 * WAD, 25 * WAD, BASE_MULTIPLIER);
        assertApproxEqAbs(price, 1e13, 1e10); // 1e-5 * 1e18

        // Test case 3: Ca = 1000000.0, Cr = 500000.0
        price = quadraticPriceFormula.spotPrice(
            1_000_000 * WAD, 500_000 * WAD, BASE_MULTIPLIER
        );
        assertApproxEqAbs(price, 2e17, 1e14); // 0.2 * 1e18

        // Test case 4: Ca = 0.1, Cr = 0.05
        price = quadraticPriceFormula.spotPrice(1e17, 5e16, BASE_MULTIPLIER);
        assertApproxEqAbs(price, 2e10, 1e7); // 2e-8 * 1e18
    }

    function testTokenOut() public {
        // Test case 1: Ca = 10000.0, in = 1.0, Cr = 50.0
        uint BCr = BASE_MULTIPLIER.fdiv(50 * WAD, WAD); // B/Cr
        uint tokensOut =
            quadraticPriceFormula.tokenOut(1 * WAD, 10_000 * WAD, BCr);
        assertApproxEqRel(tokensOut, 4.9995e18, REL_TOLERANCE);

        // Test case 2: Ca = 50.0, in = 1.0, Cr = 25.0
        BCr = BASE_MULTIPLIER.fdiv(25 * WAD, WAD);
        tokensOut = quadraticPriceFormula.tokenOut(1 * WAD, 50 * WAD, BCr);
        assertApproxEqRel(tokensOut, 98_039.22e18, REL_TOLERANCE);

        // Test case 3: Ca = 1000000.0, in = 10.0, Cr = 500000.0
        BCr = BASE_MULTIPLIER.fdiv(500_000 * WAD, WAD);
        tokensOut =
            quadraticPriceFormula.tokenOut(10 * WAD, 1_000_000 * WAD, BCr);
        assertApproxEqRel(tokensOut, 49.9995e18, REL_TOLERANCE);

        // Test case 4: Ca = 0.1, in = 0.1, Cr = 0.05
        BCr = BASE_MULTIPLIER.fdiv(5e16, WAD);
        tokensOut = quadraticPriceFormula.tokenOut(1e17, 1e17, BCr);
        assertApproxEqRel(tokensOut, 2_500_000e18, REL_TOLERANCE);
    }

    function testTokenOut_revertsIfInvalidInputAmount() public {
        // Test with capital available > 1e36
        uint largeCapitalAvailable = 2e36;
        vm.expectRevert(
            IQuadraticPriceFormula
                .QuadraticPriceFormula__InvalidInputAmount
                .selector
        );
        quadraticPriceFormula.tokenOut(1e18, largeCapitalAvailable, 1e11);

        // Test with zero capital available
        vm.expectRevert(
            IQuadraticPriceFormula
                .QuadraticPriceFormula__InvalidInputAmount
                .selector
        );
        quadraticPriceFormula.tokenOut(1e18, 0, 1e11);

        // Test when input would make total > 1e36
        uint capitalAvailable = 9e35;
        uint largeInput = 2e35;
        vm.expectRevert(
            IQuadraticPriceFormula
                .QuadraticPriceFormula__InvalidInputAmount
                .selector
        );
        quadraticPriceFormula.tokenOut(largeInput, capitalAvailable, 1e11);
    }

    function testTokenIn() public {
        // Test case 1: Ca = 10000.0, Cr = 50.0, Tokens Burned = 1
        uint BCr = BASE_MULTIPLIER.fdiv(50 * WAD, WAD); // B/Cr
        uint capitalOut =
            quadraticPriceFormula.tokenIn(1 * WAD, 10_000 * WAD, BCr);
        console.log("Test case 1 - BCr:", BCr);
        console.log("Expected:", uint(0.19999600008122798e18));
        console.log("Got:", capitalOut);
        assertApproxEqRel(capitalOut, 0.19999600008122798e18, REL_TOLERANCE);

        // Test case 2: Ca = 50.0, Cr = 25.0, Tokens Burned = 2.0
        BCr = BASE_MULTIPLIER.fdiv(25 * WAD, WAD);
        capitalOut = quadraticPriceFormula.tokenIn(2 * WAD, 50 * WAD, BCr);
        console.log("\nTest case 2 - BCr:", BCr);
        console.log("Expected:", uint(19_999_991_998_531)); // 1.9999991998531e-5 * 1e18
        console.log("Got:", capitalOut);
        assertApproxEqAbs(capitalOut, 19_999_991_998_531, 10_000_000_000);

        // Test case 3: Ca = 1000000.0, Cr = 500000.0, Tokens Burned = 100.0
        BCr = BASE_MULTIPLIER.fdiv(500_000 * WAD, WAD);
        capitalOut =
            quadraticPriceFormula.tokenIn(100 * WAD, 1_000_000 * WAD, BCr);
        console.log("\nTest case 3 - BCr:", BCr);
        console.log("Expected:", uint(19.999600007897243e18));
        console.log("Got:", capitalOut);
        assertApproxEqRel(capitalOut, 19.999600007897243e18, REL_TOLERANCE);

        // Test case 4: Ca = 0.1, Cr = 0.05, Tokens Burned = 0.5
        BCr = BASE_MULTIPLIER.fdiv(50_000_000_000_000_000, WAD);
        capitalOut = quadraticPriceFormula.tokenIn(
            500_000_000_000_000_000, 100_000_000_000_000_000, BCr
        );
        console.log("\nTest case 4 - BCr:", BCr);
        console.log("Expected:", uint(9_999_998_995)); // 9.999998995e-9 * 1e18
        console.log("Got:", capitalOut);
        assertApproxEqRel(capitalOut, 9_999_998_995, REL_TOLERANCE);
    }
}
