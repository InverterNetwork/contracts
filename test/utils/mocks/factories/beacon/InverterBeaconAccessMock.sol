pragma solidity ^0.8.0;

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";

contract InverterBeaconAccessMock is InverterBeacon {
    bool useOriginal_setImplementation = true;

    constructor(uint _majorVersion) InverterBeacon(_majorVersion) {}

    function get_implementation() public view returns (address) {
        return _implementationAddress;
    }

    //_setImplementation

    function flipUseOriginal_setImplementation() external {
        useOriginal_setImplementation = !useOriginal_setImplementation;
    }

    function original_setImplementation(
        address newImplementation,
        bool overrideShutdown
    ) public {
        _setImplementation(newImplementation, overrideShutdown);
    }

    function _setImplementation(
        address newImplementation,
        bool overrideShutdown
    ) internal virtual override {
        if (useOriginal_setImplementation) {
            super._setImplementation(newImplementation, overrideShutdown);
        } else {
            //noop
        }
    }
}
