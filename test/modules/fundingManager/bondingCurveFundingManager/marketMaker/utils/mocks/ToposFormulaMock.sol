pragma solidity ^0.8.0;

import {IToposFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/IToposFormula.sol";

contract ToposFormulaMock is IToposFormula {
    function spotPrice(uint _capitalAvailable, uint _basePriceToCaptialRatio)
        external
        view
        returns (uint)
    {}

    function tokenOut(
        uint _in,
        uint _capitalAvailable,
        uint _basePriceToCaptialRatio
    ) external view returns (uint) {}

    function tokenIn(
        uint _out,
        uint _capitalAvailable,
        uint _basePriceToCaptialRatio
    ) external view returns (uint) {}
}
