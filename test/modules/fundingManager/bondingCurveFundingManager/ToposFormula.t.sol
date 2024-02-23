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
    uint public basePriceToCaptialRatio;

    ToposFormulaMock toposFormula;

    function setUp() public {
        toposFormula = new ToposFormulaMock();
        _updateVariables();
    }

    /*  test tokenOut
        ├── when capital available is 0
        │   └── then it should revert
        ├── when tokens in + captial required is > 1e36
        │   └── then it should revert
        └── when tokens in are within bound
            └── then is should succeed TODO: add test calculations with different values
    */

    function test_RevertTokenOutWhenCaptialAvailableIsZero() public {
        // If the input is bigger inverse will give us 0.
        vm.expectRevert(IToposFormula.ToposFormula__InvalidInputAmount.selector);
        toposFormula.tokenOut(1e18, 0, basePriceToCaptialRatio);
    }

    function test_RevertTokenOutWhenInputToBig() public {
        // If the input is bigger inverse will give us 0.
        vm.expectRevert(IToposFormula.ToposFormula__InvalidInputAmount.selector);
        toposFormula.tokenOut(1e36, 1, basePriceToCaptialRatio);
    }

    function test_SucceedTokenOutWhenTokensInBound(uint _in) public view {
        _in = bound(_in, 1, 1e36 - 1);
        toposFormula.tokenOut(_in, 1, basePriceToCaptialRatio);
    }

    /*  test tokenIn
        ├── when capital available is 0
        │   └── then it should revert
        └── when tokens in are within bound
            └── then is should succeed TODO: add test calculations with different values
    */

    function test_RevertTokenInWhenCaptialAvailableIsZero() public {
        vm.expectRevert(IToposFormula.ToposFormula__InvalidInputAmount.selector);
        toposFormula.tokenIn(1, 0, basePriceToCaptialRatio);
    }

    function test_SucceedTokenInWhenTokensInBound(uint _in) public view {
        _in = bound(_in, 1, 1e36);
        toposFormula.tokenIn(_in, 1 ether, basePriceToCaptialRatio);
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

    function _setCaptialRequired(uint _newCapitalRequired) internal {
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

    /// @dev Precomputes and sets the price multiplier to captial ratio
    function _updateVariables() internal {
        basePriceToCaptialRatio = _calculateBasePriceToCaptialRatio(
            capitalRequired, basePriceMultiplier
        );
    }

    /// @dev Internal function which calculates the price multiplier to captial ratio
    function _calculateBasePriceToCaptialRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) internal pure returns (uint _basePriceToCaptialRatio) {
        _basePriceToCaptialRatio = FixedPointMathLib.fdiv(
            _basePriceMultiplier, _capitalRequired, FixedPointMathLib.WAD
        );

        if (_basePriceToCaptialRatio > 1e36) {
            revert
                IToposBondingCurveFundingManager
                .ToposBondingCurveFundingManager__InvalidInputAmount();
        }
    }
}
