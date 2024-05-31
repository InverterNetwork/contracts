// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

import {
    IModuleFactory_v1,
    IInverterBeacon_v1,
    IModule_v1,
    IOrchestrator_v1
} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {ModuleV1Mock} from "test/utils/mocks/modules/base/ModuleV1Mock.sol";

contract ModuleFactoryV1Mock is IModuleFactory_v1 {
    IInverterBeacon_v1 private _beacon;

    address public governor = address(0x99999);

    function createModule(
        IModule_v1.Metadata memory,
        IOrchestrator_v1,
        bytes memory
    ) external returns (address) {
        return address(new ModuleV1Mock());
    }

    function getBeaconAndId(IModule_v1.Metadata memory metadata)
        external
        view
        returns (IInverterBeacon_v1, bytes32)
    {
        return (_beacon, LibMetadata.identifier(metadata));
    }

    function registerMetadata(IModule_v1.Metadata memory, IInverterBeacon_v1)
        external
    {}
}
