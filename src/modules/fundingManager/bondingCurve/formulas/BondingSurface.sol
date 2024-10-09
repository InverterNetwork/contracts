// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";

import {IBondingSurface} from "@fm/bondingCurve/interfaces/IBondingSurface.sol";

/// @title Bonding surface formulas
/// @dev
///                        (C_a)^n
/// p = f(C_a, C_r) = B -------------
///                      (C_r)^(n-1)
///
/// TPG price per unit, p. The independent variables in the bonding function are the
/// capital available, C_a, and the capital required, C_r. C_a describes the amount of
/// value stored in the network at any given point in time. C_r  describes the amount
/// of value that is needed to operate the protocol according to market size
/// and conditions, the regulatory requirements, as well as the chosen risk appetite,
/// and allows for considering these three factors in the determination of p
/// Initial:
///   B := 10e-7
///   1 < n <= 2
///   n := 2
///
/// We assume n to be constant. Otherwise we would have to change the burn/mint derivations
/// on update.
contract BondingSurface is IBondingSurface, ERC165 {
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IBondingSurface).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @dev constructor
    constructor() {}

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IBondingSurface
    function spotPrice(
        uint _capitalAvailable,
        uint _capitalRequirements,
        uint _basePriceMultiplier
    ) public pure returns (uint) {
        uint caSq = FixedPointMathLib.fmul(
            _capitalAvailable, _capitalAvailable, FixedPointMathLib.WAD
        ); // C_a^2
        uint caSqCr = FixedPointMathLib.fdiv(
            caSq, _capitalRequirements, FixedPointMathLib.WAD
        );
        return FixedPointMathLib.fmul(
            caSqCr, _basePriceMultiplier, FixedPointMathLib.WAD
        ); // C_a^2 * B / C_r
    }

    /// @inheritdoc IBondingSurface
    function tokenOut(
        uint _in,
        uint _capitalAvailable,
        uint _basePriceToCapitalRatio
    ) public pure returns (uint) {
        // If the input is bigger inverse will give us 0.
        if (
            _capitalAvailable > 1e36 || _capitalAvailable + _in > 1e36
                || _capitalAvailable == 0
        ) revert BondingSurface__InvalidInputAmount();

        uint inv1 = _inverse(_capitalAvailable);
        uint inv2 = _inverse(_capitalAvailable + _in);
        uint inner = inv1 - inv2;

        return FixedPointMathLib.fmul(
            _inverse(_basePriceToCapitalRatio), inner, FixedPointMathLib.WAD
        );
    }

    /// @inheritdoc IBondingSurface
    function tokenIn(
        uint _out,
        uint _capitalAvailable,
        uint _basePriceToCapitalRatio
    ) public pure returns (uint) {
        // m * (B / C_r)
        uint BCrM = FixedPointMathLib.fmul(
            _basePriceToCapitalRatio, _out, FixedPointMathLib.WAD
        );
        // 1 / C_a_2
        uint ca2inv = _inverse(_capitalAvailable);

        return _capitalAvailable - _inverse(BCrM + ca2inv);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Computes the inverse based on
    /// https://github.com/paulrberg/prb-math/blob/86c068e21f9ba229025a77b951bd3c4c4cf103da/contracts/PRBMathUD60x18.sol#L214
    /// @param x 18 decimal fixed point number to inverse. 0 < x <= 1e36
    function _inverse(uint x) internal pure returns (uint res) {
        unchecked {
            res = 1e36 / x;
        }
    }
}
