// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Math} from "@oz/utils/math/Math.sol";

/**
 * @title   Inverter Metadata Library
 *
 * @dev     Arithmetic library with operations for fixed-point numbers.
 *
 * @author  Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
 *          Solady (https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)
 */
library FixedPointMathLib {
    /*///////////////////////////////////////////////////////////////
                            COMMON BASE UNITS
    //////////////////////////////////////////////////////////////*/

    uint internal constant YAD = 1e8;
    uint internal constant WAD = 1e18;
    uint internal constant RAY = 1e27;
    uint internal constant RAD = 1e45;

    /*///////////////////////////////////////////////////////////////
                         FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function fmul(uint x, uint y, uint baseUnit)
        internal
        pure
        returns (uint z)
    {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(x == 0 || (x * y) / x == y)
            if iszero(or(iszero(x), eq(div(z, x), y))) { revert(0, 0) }

            // If baseUnit is zero this will return zero instead of reverting.
            z := div(z, baseUnit)
        }
    }

    function fdiv(uint x, uint y, uint baseUnit)
        internal
        pure
        returns (uint z)
    {
        assembly {
            // Store x * baseUnit in z for now.
            z := mul(x, baseUnit)

            // Equivalent to require(y != 0 && (x == 0 || (x * baseUnit) / x == baseUnit))
            if iszero(
                and(iszero(iszero(y)), or(iszero(x), eq(div(z, x), baseUnit)))
            ) { revert(0, 0) }

            // We ensure y is not zero above, so there is never division by zero here.
            z := div(z, y)
        }
    }

    function fpow(uint x, uint n, uint baseUnit)
        internal
        pure
        returns (uint z)
    {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    // 0 ** 0 = 1
                    z := baseUnit
                }
                default {
                    // 0 ** n = 0
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    // If n is even, store baseUnit in z for now.
                    z := baseUnit
                }
                default {
                    // If n is odd, store x in z for now.
                    z := x
                }

                // Shifting right by 1 is like dividing by 2.
                let half := shr(1, baseUnit)

                for {
                    // Shift n right by 1 before looping to halve it.
                    n := shr(1, n)
                } n {
                    // Shift n right by 1 each iteration to halve it.
                    n := shr(1, n)
                } {
                    // Revert immediately if x ** 2 would overflow.
                    // Equivalent to iszero(eq(div(xx, x), x)) here.
                    if shr(128, x) { revert(0, 0) }

                    // Store x squared.
                    let xx := mul(x, x)

                    // Round to the nearest number.
                    let xxRound := add(xx, half)

                    // Revert if xx + half overflowed.
                    if lt(xxRound, xx) { revert(0, 0) }

                    // Set x to scaled xxRound.
                    x := div(xxRound, baseUnit)

                    // If n is even:
                    if mod(n, 2) {
                        // Compute z * x.
                        let zx := mul(z, x)

                        // If z * x overflowed:
                        if iszero(eq(div(zx, x), z)) {
                            // Revert if x is non-zero.
                            if iszero(iszero(x)) { revert(0, 0) }
                        }

                        // Round to the nearest number.
                        let zxRound := add(zx, half)

                        // Revert if zx + half overflowed.
                        if lt(zxRound, zx) { revert(0, 0) }

                        // Return properly scaled zxRound.
                        z := div(zxRound, baseUnit)
                    }
                }
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                        GENERAL NUMBER UTILITIES
    //////////////////////////////////////////////////////////////*/

    function sqrt(uint x) internal pure returns (uint z) {
        assembly {
            // Start off with z at 1.
            z := 1

            // Used below to help find a nearby power of 2.
            let y := x

            // Find the lowest power of 2 that is at least sqrt(x).
            if iszero(lt(y, 0x100000000000000000000000000000000)) {
                y := shr(128, y) // Like dividing by 2 ** 128.
                z := shl(64, z)
            }
            if iszero(lt(y, 0x10000000000000000)) {
                y := shr(64, y) // Like dividing by 2 ** 64.
                z := shl(32, z)
            }
            if iszero(lt(y, 0x100000000)) {
                y := shr(32, y) // Like dividing by 2 ** 32.
                z := shl(16, z)
            }
            if iszero(lt(y, 0x10000)) {
                y := shr(16, y) // Like dividing by 2 ** 16.
                z := shl(8, z)
            }
            if iszero(lt(y, 0x100)) {
                y := shr(8, y) // Like dividing by 2 ** 8.
                z := shl(4, z)
            }
            if iszero(lt(y, 0x10)) {
                y := shr(4, y) // Like dividing by 2 ** 4.
                z := shl(2, z)
            }
            if iszero(lt(y, 0x8)) {
                // Equivalent to 2 ** z.
                z := shl(1, z)
            }

            // Shifting right by 1 is like dividing by 2.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // Compute a rounded down version of z.
            let zRoundDown := div(x, z)

            // If zRoundDown is smaller, use it.
            if lt(zRoundDown, z) { z := zRoundDown }
        }
    }

    // These implementations are copied from the Solady library

    function _mulmod(uint a_, uint b_, uint modulus_)
        internal
        pure
        returns (uint)
    {
        require(
            modulus_ > 0,
            "DiscreteCurveMathLib_v1: modulus_ cannot be zero in _mulmod"
        );
        return (a_ * b_) % modulus_;
    }

    function _mulDivUp(uint a_, uint b_, uint denominator_)
        internal
        pure
        returns (uint result_)
    {
        require(
            denominator_ > 0,
            "DiscreteCurveMathLib_v1: division by zero in _mulDivUp"
        );
        result_ = Math.mulDiv(a_, b_, denominator_); // Standard OpenZeppelin Math.mulDiv rounds down (floor division)

        // If there's any remainder from (a_ * b_) / denominator_, we need to add 1 to round up.
        // A remainder exists if (a_ * b_) % denominator_ is not 0.
        // We use the local _mulmod function which safely computes (a_ * b_) % denominator_.
        if (_mulmod(a_, b_, denominator_) > 0) {
            // Before incrementing, check if 'result_' is already at max_uint256 to prevent overflow.
            // This scenario (overflowing after adding 1 due to rounding) is extremely unlikely if a_, b_, denominator_
            // are such that mulDiv itself doesn't revert, but it's a good safety check.
            require(
                result_ < type(uint).max,
                "DiscreteCurveMathLib_v1: _mulDivUp overflow on increment"
            );
            result_++;
        }
        return result_;
    }
}
