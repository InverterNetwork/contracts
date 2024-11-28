pragma solidity ^0.8.0;

contract IssuanceTokenWrapperMock {
    address public issuanceToken;

    constructor(address _issuanceToken) {
        issuanceToken = _issuanceToken;
    }

    function decimals() public view returns (uint8) {
        return 18;
    }
}
