pragma solidity 0.8.19;

import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

contract BeaconMock is IBeacon {
    /// @inheritdoc IBeacon
    address public implementation;

    function overrideImplementation(address implementation_) public {
        implementation = implementation_;
    }
}
