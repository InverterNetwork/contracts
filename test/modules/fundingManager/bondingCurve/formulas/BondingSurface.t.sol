// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import {IBondingSurface} from
    "src/modules/fundingManager/bondingCurve/interfaces/IBondingSurface.sol";
import {BondingSurface} from
    "src/modules/fundingManager/bondingCurve/formulas/BondingSurface.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";

contract BondingSurface_Test is Test {
    using FixedPointMathLib for uint;

    BondingSurface public bondingSurface;
    uint constant BASE_MULTIPLIER = 1e11; // 10^-7 * 1e18
    uint constant WAD = 1e18;
    uint constant REL_TOLERANCE = 1e12; // 0.0001% relative tolerance for complex calculations

    function setUp() public {
        bondingSurface = new BondingSurface();
    }

    function testSupportsInterface() public {
        // Test for IBondingSurface interface support
        bytes4 interfaceId = type(IBondingSurface).interfaceId;
        assertTrue(bondingSurface.supportsInterface(interfaceId));

        // Test for ERC165 interface support
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(bondingSurface.supportsInterface(erc165InterfaceId));

        // Test for non-supported interface
        bytes4 randomInterfaceId = 0x12345678;
        assertFalse(bondingSurface.supportsInterface(randomInterfaceId));
    }

    function testSpotPrice() public {
        // Test case 1: Ca = 10000.0, Cr = 50.0
        uint price =
            bondingSurface.spotPrice(10_000 * WAD, 50 * WAD, BASE_MULTIPLIER);
        assertApproxEqAbs(price, 2e17, 1e14); // 0.2 * 1e18

        // Test case 2: Ca = 50.0, Cr = 25.0
        price = bondingSurface.spotPrice(50 * WAD, 25 * WAD, BASE_MULTIPLIER);
        assertApproxEqAbs(price, 1e13, 1e10); // 1e-5 * 1e18

        // Test case 3: Ca = 1000000.0, Cr = 500000.0
        price = bondingSurface.spotPrice(
            1_000_000 * WAD, 500_000 * WAD, BASE_MULTIPLIER
        );
        assertApproxEqAbs(price, 2e17, 1e14); // 0.2 * 1e18

        // Test case 4: Ca = 0.1, Cr = 0.05
        price = bondingSurface.spotPrice(1e17, 5e16, BASE_MULTIPLIER);
        assertApproxEqAbs(price, 2e10, 1e7); // 2e-8 * 1e18
    }

    function testTokenOut() public {
        // Test case 1: Ca = 10000.0, in = 1.0, Cr = 50.0
        uint BCr = BASE_MULTIPLIER.fdiv(50 * WAD, WAD); // B/Cr
        uint tokensOut = bondingSurface.tokenOut(1 * WAD, 10_000 * WAD, BCr);
        assertApproxEqRel(tokensOut, 4.9995e18, REL_TOLERANCE); // 4.9995 * 1e18

        // Test case 2: Ca = 50.0, in = 1.0, Cr = 25.0
        BCr = BASE_MULTIPLIER.fdiv(25 * WAD, WAD);
        tokensOut = bondingSurface.tokenOut(1 * WAD, 50 * WAD, BCr);
        assertApproxEqRel(tokensOut, 98_039.22e18, REL_TOLERANCE); // 98039.22 * 1e18

        // Test case 3: Ca = 1000000.0, in = 10.0, Cr = 500000.0
        BCr = BASE_MULTIPLIER.fdiv(500_000 * WAD, WAD);
        tokensOut = bondingSurface.tokenOut(10 * WAD, 1_000_000 * WAD, BCr);
        assertApproxEqRel(tokensOut, 49.9995e18, REL_TOLERANCE); // 49.9995 * 1e18

        // Test case 4: Ca = 0.1, in = 0.1, Cr = 0.05
        BCr = BASE_MULTIPLIER.fdiv(5e16, WAD);
        tokensOut = bondingSurface.tokenOut(1e17, 1e17, BCr);
        assertApproxEqRel(tokensOut, 2_500_000e18, REL_TOLERANCE); // 2500000.0 * 1e18
    }

    function testTokenOut_revertsIfInvalidInputAmount() public {
        // Test with capital available > 1e36
        uint largeCapitalAvailable = 2e36;
        vm.expectRevert(
            IBondingSurface.BondingSurface__InvalidInputAmount.selector
        );
        bondingSurface.tokenOut(1e18, largeCapitalAvailable, 1e11);

        // Test with zero capital available
        vm.expectRevert(
            IBondingSurface.BondingSurface__InvalidInputAmount.selector
        );
        bondingSurface.tokenOut(1e18, 0, 1e11);

        // Test when input would make total > 1e36
        uint capitalAvailable = 9e35;
        uint largeInput = 2e35;
        vm.expectRevert(
            IBondingSurface.BondingSurface__InvalidInputAmount.selector
        );
        bondingSurface.tokenOut(largeInput, capitalAvailable, 1e11);
    }

    function testTokenIn() public {
        // Test case 1: Ca = 10000.0, Cr = 50.0
        uint BCr = BASE_MULTIPLIER.fdiv(50 * WAD, WAD); // B/Cr
        uint capitalOut = bondingSurface.tokenIn(1 * WAD, 10_000 * WAD, BCr);
        console.log("Test case 1 - BCr:", BCr);
        console.log("Expected:", uint(199_996_000_000_000_000)); // 0.199996 * 1e18
        console.log("Got:", capitalOut);
        assertApproxEqRel(capitalOut, 199_996_000_000_000_000, REL_TOLERANCE); // 0.199996 * 1e18

        // Test case 2: Ca = 50.0, Cr = 25.0
        BCr = BASE_MULTIPLIER.fdiv(25 * WAD, WAD);
        capitalOut = bondingSurface.tokenIn(1 * WAD, 50 * WAD, BCr);
        console.log("\nTest case 2 - BCr:", BCr);
        console.log("Expected:", uint(19_999_900_000_000)); // 1.99999e-5 * 1e18
        console.log("Got:", capitalOut);
        assertApproxEqRel(capitalOut, 19_999_900_000_000, REL_TOLERANCE); // 1.99999e-5 * 1e18

        // Test case 3: Ca = 1000000.0, Cr = 500000.0
        BCr = BASE_MULTIPLIER.fdiv(500_000 * WAD, WAD);
        capitalOut = bondingSurface.tokenIn(1 * WAD, 1_000_000 * WAD, BCr);
        console.log("\nTest case 3 - BCr:", BCr);
        console.log("Expected:", uint(19_999_600_000_000_000_000)); // 19.9996 * 1e18
        console.log("Got:", capitalOut);
        assertApproxEqRel(capitalOut, 19_999_600_000_000_000_000, REL_TOLERANCE); // 19.9996 * 1e18

        // Test case 4: Ca = 0.1, Cr = 0.05
        BCr = BASE_MULTIPLIER.fdiv(5e16, WAD);
        capitalOut = bondingSurface.tokenIn(1 * WAD, 1e17, BCr);
        console.log("\nTest case 4 - BCr:", BCr);
        console.log("Expected:", uint(999_999_000_000)); // 9.99999e-9 * 1e18
        console.log("Got:", capitalOut);
        assertApproxEqRel(capitalOut, 999_999_000_000, REL_TOLERANCE); // 9.99999e-9 * 1e18
    }
}
