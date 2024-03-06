// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ToposFormulaMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/ToposFormulaMock.sol";
import {IToposFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/IToposFormula.sol";
import {FixedPointMathLib} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/FixedPointMathLib.sol";
import {IToposBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/IToposBondingCurveFundingManager.sol";

contract ToposFormulaTest is Test {
    uint public basePriceMultiplier = 0.000001 ether;
    uint public capitalRequired = 1_000_000 * 1e18;
    uint public basePriceToCapitalRatio;

    ToposFormulaMock toposFormula;

    function setUp() public {
        toposFormula = new ToposFormulaMock();
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
        vm.expectRevert(IToposFormula.ToposFormula__InvalidInputAmount.selector);
        toposFormula.tokenOut(1e18, 0, basePriceToCapitalRatio);
    }

    function test_RevertTokenOutWhenInputToBig() public {
        // If the input is bigger inverse will give us 0.
        vm.expectRevert(IToposFormula.ToposFormula__InvalidInputAmount.selector);
        toposFormula.tokenOut(1e36, 1, basePriceToCapitalRatio);
    }

    function test_SucceedTokenOutWhenTokensInBound(uint _in) public view {
        console.logUint(basePriceToCapitalRatio);
        _in = bound(_in, 1, 1e36 - 1);
        toposFormula.tokenOut(_in, 1, basePriceToCapitalRatio);
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
        toposFormula.tokenIn(1, 0, basePriceToCapitalRatio);
    }

    function test_SucceedTokenInWhenTokensInBound(uint _in) public view {
        _in = bound(_in, 1, 1e36);
        toposFormula.tokenIn(_in, 1 ether, basePriceToCapitalRatio);
    }

    // Testing values are taken from matlab simulations
    function testSpotPriceManual() public {
        assertEq(basePriceMultiplier, 0.000001 ether); // from test #027

        assertEq(
            toposFormula.spotPrice(1e18, 1e3 ether, basePriceMultiplier), 1e9
        );
        assertEq(
            toposFormula.spotPrice(1e3 ether, 1e3 ether, basePriceMultiplier),
            1e15
        );

        assertEq(
            toposFormula.spotPrice(1e3 ether, 1e15 ether, basePriceMultiplier),
            1e3
        );
        assertEq(
            toposFormula.spotPrice(1e6 ether, 1e15 ether, basePriceMultiplier),
            1e9
        );
        assertEq(
            toposFormula.spotPrice(1e9 ether, 1e15 ether, basePriceMultiplier),
            1e15
        );
        assertEq(
            toposFormula.spotPrice(1e12 ether, 1e15 ether, basePriceMultiplier),
            1e3 ether
        );
        assertEq(
            toposFormula.spotPrice(1e15 ether, 1e15 ether, basePriceMultiplier),
            1e9 ether
        );
        assertEq(
            toposFormula.spotPrice(1e18 ether, 1e15 ether, basePriceMultiplier),
            1e15 ether
        );

        assertEq(
            toposFormula.spotPrice(1e3 ether, 1e18 ether, basePriceMultiplier),
            1
        );
        assertEq(
            toposFormula.spotPrice(1e6 ether, 1e18 ether, basePriceMultiplier),
            1e6
        );
        assertEq(
            toposFormula.spotPrice(1e9 ether, 1e18 ether, basePriceMultiplier),
            1e12
        );
        assertEq(
            toposFormula.spotPrice(1e12 ether, 1e18 ether, basePriceMultiplier),
            1 ether
        );
        assertEq(
            toposFormula.spotPrice(1e15 ether, 1e18 ether, basePriceMultiplier),
            1e6 ether
        );
        assertEq(
            toposFormula.spotPrice(1e18 ether, 1e18 ether, basePriceMultiplier),
            1e12 ether
        );
    }

    //--------------------------------------------------------------------------
    // Helper functions

    function _setCapitalRequired(uint _newCapitalRequired) internal {
        if (_newCapitalRequired == 0) {
            revert
                IToposBondingCurveFundingManager
                .ToposBondingCurveFundingManager__InvalidInputAmount();
        }
        capitalRequired = _newCapitalRequired;
        _updateVariables();
    }

    function _setBaseMultiplier(uint _newBasePriceMultiplier) internal {
        if (_newBasePriceMultiplier == 0) {
            revert
                IToposBondingCurveFundingManager
                .ToposBondingCurveFundingManager__InvalidInputAmount();
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
                IToposBondingCurveFundingManager
                .ToposBondingCurveFundingManager__InvalidInputAmount();
        }
    }
}
