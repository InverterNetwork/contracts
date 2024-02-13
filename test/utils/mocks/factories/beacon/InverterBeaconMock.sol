pragma solidity ^0.8.0;

import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

contract InverterBeaconMock is IInverterBeacon {
    address public implementation;

    function overrideImplementation(address implementation_) public {
        implementation = implementation_;
    }

    function version() external view returns (uint, uint) {
        return (0, 0);
    }

    function upgradeTo(address, uint) external {}
}
