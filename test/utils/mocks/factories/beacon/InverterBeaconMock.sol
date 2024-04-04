pragma solidity ^0.8.0;

import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

import {ERC165} from "@oz/utils/introspection/ERC165.sol";

contract InverterBeaconMock is IInverterBeacon, ERC165 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IInverterBeacon).interfaceId
            || super.supportsInterface(interfaceId);
    }

    address public implementation;

    bool public emergencyMode;

    uint public majorVersion;
    uint public minorVersion;

    uint public functionCalled;

    function overrideImplementation(address implementation_) public {
        implementation = implementation_;
    }

    function overrideVersion(uint majorVersion_, uint minorVersion_) public {
        majorVersion = majorVersion_;
        minorVersion = minorVersion_;
    }

    function overrideEmergencyMode(bool emergencyMode_) public {
        emergencyMode = emergencyMode_;
    }

    function version() external view returns (uint, uint) {
        return (majorVersion, minorVersion);
    }

    function emergencyModeActive() external view returns (bool) {
        return emergencyMode;
    }

    function upgradeTo(address, uint, bool) external {
        functionCalled++; //@todo use address uint and bool
    }

    function shutDownImplementation() external {
        functionCalled++;
    }

    function restartImplementation() external {
        functionCalled++;
    }
}
