pragma solidity ^0.8.0;

import {Beacon} from "src/factories/beacon-fundamentals/Beacon.sol";

contract BeaconMock is Beacon {
    address private _implementation;

    function overrideImplementation(address newImplementation) public {
        _implementation = newImplementation;
    }

    function implementation() public view override returns (address) {
        return _implementation;
    }
}
