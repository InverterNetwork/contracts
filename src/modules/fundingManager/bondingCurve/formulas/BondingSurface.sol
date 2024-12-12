// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";

import {IBondingSurface} from "@fm/bondingCurve/interfaces/IBondingSurface.sol";

/**
 * @title   Bonding Surface Formula
 *
 * @notice  Bonding Surface Formular to calculate the price of a token in the
 *          bonding curve.
 *
 * @dev
 *                                (C_a)^n
 *          p = f(C_a, C_r) = B -------------
 *                              (C_r)^(n-1)
 *
 *          TPG price per unit, p. The independent variables in the bonding
 *          function are the capital available, C_a, and the capital required,
 *          C_r. C_a describes the amount of value stored in the network at any
 *          given point in time. C_r  describes the amount of value that is
 *          needed to operate the protocol according to market size and
 *          conditions, the regulatory requirements, as well as the chosen risk
 *          appetite, and allows for considering these three factors in the
 *          determination of p
 *          Initial:
 *            B := 10e-7
 *            1 < n <= 2
 *            n := 2
 *
 *          We assume n to be constant. Otherwise we would have to change the
 *          burn/mint derivations on update.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version v1.0.0
 *
 * @custom:inverter-standard-version 0.1.0
 *
 * @author  Inverter Network
 */
contract BondingSurface is IBondingSurface, ERC165 {
    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(ERC165)
        returns (bool supportsInterface_)
    {
        return interfaceId_ == type(IBondingSurface).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // ========================================================================
    // Public Getter Functions

    /// @inheritdoc IBondingSurface
    function spotPrice(
        uint capitalAvailable_,
        uint capitalRequirements_,
        uint basePriceMultiplier_
    ) public pure returns (uint spotPrice_) {
        uint caSq = FixedPointMathLib.fmul(
            capitalAvailable_, capitalAvailable_, FixedPointMathLib.WAD
        ); // C_a^2
        uint caSqCr = FixedPointMathLib.fdiv(
            caSq, capitalRequirements_, FixedPointMathLib.WAD
        );
        return FixedPointMathLib.fmul(
            caSqCr, basePriceMultiplier_, FixedPointMathLib.WAD
        ); // C_a^2 * B / C_r
    }

    /// @inheritdoc IBondingSurface
    function tokenOut(
        uint in_,
        uint capitalAvailable_,
        uint basePriceToCapitalRatio_
    ) public pure returns (uint amount_) {
        // If the input is bigger inverse will give us 0.
        if (
            capitalAvailable_ > 1e36 || capitalAvailable_ + in_ > 1e36
                || capitalAvailable_ == 0
        ) revert BondingSurface__InvalidInputAmount();

        uint inv1 = _inverse(capitalAvailable_);
        uint inv2 = _inverse(capitalAvailable_ + in_);
        uint inner = inv1 - inv2;

        return FixedPointMathLib.fmul(
            _inverse(basePriceToCapitalRatio_), inner, FixedPointMathLib.WAD
        );
    }

    /// @inheritdoc IBondingSurface
    function tokenIn(
        uint out_,
        uint capitalAvailable_,
        uint basePriceToCapitalRatio_
    ) public pure returns (uint amount_) {
        // m * (B / C_r)
        uint BCrM = FixedPointMathLib.fmul(
            basePriceToCapitalRatio_, out_, FixedPointMathLib.WAD
        );
        // 1 / C_a_2
        uint ca2inv = _inverse(capitalAvailable_);

        return capitalAvailable_ - _inverse(BCrM + ca2inv);
    }

    // ========================================================================
    // Internal Functions

    /// @notice Computes the inverse based on
    /// @dev    https://github.com/paulrberg/prb-math/blob/86c068e21f9ba229025a77b951bd3c4c4cf103da/contracts/PRBMathUD60x18.sol#L214
    /// @param x_ 18 decimal fixed point number to inverse. 0 < x <= 1e36
    function _inverse(uint x_) internal pure returns (uint res_) {
        unchecked {
            res_ = 1e36 / x_;
        }
    }
}
