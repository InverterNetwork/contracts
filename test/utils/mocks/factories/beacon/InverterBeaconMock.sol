pragma solidity ^0.8.0;

import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

contract InverterBeaconMock is IInverterBeacon {
    address public implementation;

    uint public majorVersion;
    uint public minorVersion;

    function overrideImplementation(address implementation_) public {
        implementation = implementation_;
    }

    function overrideVersion(uint majorVersion_, uint minorVersion_) public {
        majorVersion = majorVersion_;
        minorVersion = minorVersion_;
    }

    function version() external view returns (uint, uint) {
        return (majorVersion, minorVersion);
    }

    function upgradeTo(address, uint) external {}
}
