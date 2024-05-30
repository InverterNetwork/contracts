pragma solidity ^0.8.0;

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

contract InverterBeaconV1AccessMock is InverterBeacon_v1 {
    bool useOriginal_setImplementation = true;

    constructor(
        address owner,
        uint _majorVersion,
        address _implementation,
        uint _minorVersion
    ) InverterBeacon_v1(owner, _majorVersion, _implementation, _minorVersion) {}

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
