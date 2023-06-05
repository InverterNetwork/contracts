// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

import {
    IModuleFactory,
    IBeacon,
    IModule,
    IProposal
} from "src/factories/IModuleFactory.sol";

contract ModuleFactoryMock is IModuleFactory {
    IBeacon private _beacon;

    // Note to not start too low as, e.g., modules are not allowed to have
    // address(0x1).
    uint public addressCounter = 10;

    function createModule(IModule.Metadata memory, IProposal, bytes memory)
        external
        returns (address)
    {
        return address(uint160(++addressCounter));
    }

    function getBeaconAndId(IModule.Metadata memory metadata)
        external
        view
        returns (IBeacon, bytes32)
    {
        return (_beacon, LibMetadata.identifier(metadata));
    }

    function registerMetadata(IModule.Metadata memory, IBeacon) external {}
}
