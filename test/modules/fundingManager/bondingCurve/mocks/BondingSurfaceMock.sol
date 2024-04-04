pragma solidity ^0.8.0;

import {IBondingSurface} from
    "src/modules/fundingManager/bondingCurve/interfaces/IBondingSurface.sol";

contract BondingSurfaceMock is IBondingSurface {
    function spotPrice(uint _capitalAvailable, uint _basePriceToCapitalRatio)
        external
        view
        returns (uint)
    {}

    function tokenOut(
        uint _in,
        uint _capitalAvailable,
        uint _basePriceToCapitalRatio
    ) external view returns (uint) {}

    function tokenIn(
        uint _out,
        uint _capitalAvailable,
        uint _basePriceToCapitalRatio
    ) external view returns (uint) {}
}
