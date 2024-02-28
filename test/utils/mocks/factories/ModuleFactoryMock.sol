// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

import {
    IModuleFactory,
    IInverterBeacon,
    IModule,
    IOrchestrator
} from "src/factories/IModuleFactory.sol";

contract ModuleFactoryMock is IModuleFactory {
    IInverterBeacon private _beacon;

    // Note to not start too low as, e.g., modules are not allowed to have
    // address(0x1).
    uint public addressCounter = 10;

    function createModule(IModule.Metadata memory, IOrchestrator, bytes memory)
        external
        returns (address)
    {
        return address(uint160(++addressCounter));
    }

    function getBeaconAndId(IModule.Metadata memory metadata)
        external
        view
        returns (IInverterBeacon, bytes32)
    {
        return (_beacon, LibMetadata.identifier(metadata));
    }

    function registerMetadata(IModule.Metadata memory, IInverterBeacon)
        external
    {}
}
