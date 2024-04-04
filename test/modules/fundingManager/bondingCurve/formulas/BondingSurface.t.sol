// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {BondingSurfaceMock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/BondingSurfaceMock.sol";
import {IBondingSurface} from
    "src/modules/fundingManager/bondingCurve/interfaces/IBondingSurface.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";
import {IFM_BC_BondingSurface_Repayer_Seizable_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_BondingSurface_Repayer_Seizable_v1.sol";

contract BondingSurfaceTest is Test {
    uint public basePriceMultiplier = 0.000001 ether;
    uint public capitalRequired = 1_000_000 * 1e18;
    uint public basePriceToCapitalRatio;

    BondingSurfaceMock formula;

    function setUp() public {
        formula = new BondingSurfaceMock();
        _updateVariables();
    }

    /*  test tokenOut
        ├── Given: capital available is 0
        │   └── When: the function tokenOut() is called
        │       └── then it should revert
        ├── Give: tokens in + capital required is > 1e36
        │   └── When: the function tokenOut() is called
        │       └── then it should revert
        └── Given tokens in are within bound
            └── When: the function tokenOut() is called
                └── then is should succeed
    */

    function test_RevertTokenOutWhenCapitalAvailableIsZero() public {
        // If the input is bigger inverse will give us 0.
        vm.expectRevert(
            IBondingSurface.BondingSurface__InvalidInputAmount.selector
        );
        formula.tokenOut(1e18, 0, basePriceToCapitalRatio);
    }

    function test_RevertTokenOutWhenInputToBig() public {
        // If the input is bigger inverse will give us 0.
        vm.expectRevert(
            IBondingSurface.BondingSurface__InvalidInputAmount.selector
        );
        formula.tokenOut(1e36, 1, basePriceToCapitalRatio);
    }

    function test_SucceedTokenOutWhenTokensInBound(uint _in) public view {
        console.logUint(basePriceToCapitalRatio);
        _in = bound(_in, 1, 1e36 - 1);
        formula.tokenOut(_in, 1, basePriceToCapitalRatio);
    }

    /*  test tokenIn
        ├── Given: capital available == 0
        │   └── When: the function tokenIn() gets called
        │       └── Then: it should revert
        └── Given: values are in bound
            └── When: the function tokenIn() gets called
                └── Then: it should succeed
    */

    function test_RevertTokenInWhenCapitalAvailableIsZero() public {
        vm.expectRevert();
        formula.tokenIn(1, 0, basePriceToCapitalRatio);
    }

    function test_SucceedTokenInWhenTokensInBound(uint _in) public view {
        _in = bound(_in, 1, 1e36);
        formula.tokenIn(_in, 1 ether, basePriceToCapitalRatio);
    }

    // Testing values are taken from matlab simulations
    function testSpotPriceManual() public {
        assertEq(basePriceMultiplier, 0.000001 ether); // from test #027

        assertEq(formula.spotPrice(1e18, 1e3 ether, basePriceMultiplier), 1e9);
        assertEq(
            formula.spotPrice(1e3 ether, 1e3 ether, basePriceMultiplier), 1e15
        );

        assertEq(
            formula.spotPrice(1e3 ether, 1e15 ether, basePriceMultiplier), 1e3
        );
        assertEq(
            formula.spotPrice(1e6 ether, 1e15 ether, basePriceMultiplier), 1e9
        );
        assertEq(
            formula.spotPrice(1e9 ether, 1e15 ether, basePriceMultiplier), 1e15
        );
        assertEq(
            formula.spotPrice(1e12 ether, 1e15 ether, basePriceMultiplier),
            1e3 ether
        );
        assertEq(
            formula.spotPrice(1e15 ether, 1e15 ether, basePriceMultiplier),
            1e9 ether
        );
        assertEq(
            formula.spotPrice(1e18 ether, 1e15 ether, basePriceMultiplier),
            1e15 ether
        );

        assertEq(
            formula.spotPrice(1e3 ether, 1e18 ether, basePriceMultiplier), 1
        );
        assertEq(
            formula.spotPrice(1e6 ether, 1e18 ether, basePriceMultiplier), 1e6
        );
        assertEq(
            formula.spotPrice(1e9 ether, 1e18 ether, basePriceMultiplier), 1e12
        );
        assertEq(
            formula.spotPrice(1e12 ether, 1e18 ether, basePriceMultiplier),
            1 ether
        );
        assertEq(
            formula.spotPrice(1e15 ether, 1e18 ether, basePriceMultiplier),
            1e6 ether
        );
        assertEq(
            formula.spotPrice(1e18 ether, 1e18 ether, basePriceMultiplier),
            1e12 ether
        );
    }

    //--------------------------------------------------------------------------
    // Helper functions

    function _setCapitalRequired(uint _newCapitalRequired) internal {
        if (_newCapitalRequired == 0) {
            revert
                IFM_BC_BondingSurface_Repayer_Seizable_v1
                .FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidInputAmount();
        }
        capitalRequired = _newCapitalRequired;
        _updateVariables();
    }

    function _setBasePriceMultiplier(uint _newBasePriceMultiplier) internal {
        if (_newBasePriceMultiplier == 0) {
            revert
                IFM_BC_BondingSurface_Repayer_Seizable_v1
                .FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidInputAmount();
        }
        basePriceMultiplier = _newBasePriceMultiplier;
        _updateVariables();
    }

    /// @dev Precomputes and sets the price multiplier to capital ratio
    function _updateVariables() internal {
        basePriceToCapitalRatio = _calculateBasePriceToCapitalRatio(
            capitalRequired, basePriceMultiplier
        );
    }

    /// @dev Internal function which calculates the price multiplier to capital ratio
    function _calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) internal pure returns (uint _basePriceToCapitalRatio) {
        _basePriceToCapitalRatio = FixedPointMathLib.fdiv(
            _basePriceMultiplier, _capitalRequired, FixedPointMathLib.WAD
        );

        if (_basePriceToCapitalRatio > 1e36) {
            revert
                IFM_BC_BondingSurface_Repayer_Seizable_v1
                .FM_BC_BondingSurface_Repayer_Seizable_v1__InvalidInputAmount();
        }
    }
}
