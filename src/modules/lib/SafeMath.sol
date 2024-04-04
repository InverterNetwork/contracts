pragma solidity 0.8.23;

/// @title  Aragon SafeMath Library
/// @author https://github.com/AragonBlack/fundraising/blob/master/apps/bancor-formula/contracts/utility/SafeMath.sol
/// @notice The sole modification implemented in the contract involves altering the Solidity version number.

/*
    Library for basic math operations with overflow/underflow protection
*/
library SafeMath {
    /**
     * @dev returns the sum of _x and _y, reverts if the calculation overflows
     *
     *     @param _x   value 1
     *     @param _y   value 2
     *
     *     @return sum
     */
    function add(uint _x, uint _y) internal pure returns (uint) {
        uint z = _x + _y;
        require(z >= _x);
        return z;
    }

    /**
     * @dev returns the difference of _x minus _y, reverts if the calculation underflows
     *
     *     @param _x   minuend
     *     @param _y   subtrahend
     *
     *     @return difference
     */
    function sub(uint _x, uint _y) internal pure returns (uint) {
        require(_x >= _y);
        return _x - _y;
    }

    /**
     * @dev returns the product of multiplying _x by _y, reverts if the calculation overflows
     *
     *     @param _x   factor 1
     *     @param _y   factor 2
     *
     *     @return product
     */
    function mul(uint _x, uint _y) internal pure returns (uint) {
        // gas optimization
        if (_x == 0) {
            return 0;
        }

        uint z = _x * _y;
        require(z / _x == _y);
        return z;
    }

    /**
     * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
     *
     *     @param _x   dividend
     *     @param _y   divisor
     *
     *     @return quotient
     */
    function div(uint _x, uint _y) internal pure returns (uint) {
        require(_y > 0);
        uint c = _x / _y;

        return c;
    }
}
