pragma solidity 0.8.19;
/// TODO: Add license

/*
    Utilities & Common Modifiers
*/
contract BancorUtils {
    /**
     * constructor
     */
    constructor() {}

    // verifies that an amount is greater than zero
    modifier greaterThanZero(uint _amount) {
        require(_amount > 0);
        _;
    }

    // validates an address - currently only checks that it isn't null
    modifier validAddress(address _address) {
        require(_address != address(0));
        _;
    }

    // verifies that the address is different than this contract address
    modifier notThis(address _address) {
        require(_address != address(this));
        _;
    }
}
