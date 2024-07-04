pragma solidity ^0.8.0;

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

import {ERC165} from "@oz/utils/introspection/ERC165.sol";

contract InverterBeaconV1Mock is IInverterBeacon_v1, ERC165 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IInverterBeacon_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    address public implementation;

    bool public emergencyMode;

    uint public majorVersion;
    uint public minorVersion;
    uint public patchVersion;

    uint public functionCalled;
    bool public forcefulCall;

    function overrideImplementation(address implementation_) public {
        implementation = implementation_;
    }

    function overrideVersion(
        uint majorVersion_,
        uint minorVersion_,
        uint patchVersion_
    ) public {
        majorVersion = majorVersion_;
        minorVersion = minorVersion_;
        patchVersion = patchVersion_;
    }

    function overrideEmergencyMode(bool emergencyMode_) public {
        emergencyMode = emergencyMode_;
    }

    function version() external view returns (uint, uint, uint) {
        return (majorVersion, minorVersion, patchVersion);
    }

    function getImplementationAddress() external view returns (address) {
        return implementation;
    }

    function emergencyModeActive() external view returns (bool) {
        return emergencyMode;
    }

    function upgradeTo(address impl, uint minor, uint patch, bool force)
        external
    {
        functionCalled++;
        implementation = impl;
        minorVersion = minor;
        patchVersion = patch;
        forcefulCall = force;
    }

    function shutDownImplementation() external {
        functionCalled++;
    }

    function restartImplementation() external {
        functionCalled++;
    }
}
