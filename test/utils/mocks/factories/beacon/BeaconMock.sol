pragma solidity ^0.8.0;

import {Beacon} from "src/factories/beacon/Beacon.sol";

// @todo felix, mp: It's not a mock if it inherits from the stuff it should mock.
contract BeaconMock is Beacon {
    address private _implementation;

    function overrideImplementation(address newImplementation) public {
        _implementation = newImplementation;
    }

    function implementation() public view override returns (address) {
        return _implementation;
    }
}
