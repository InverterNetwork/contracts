// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModuleFactory} from "src/interfaces/IModuleFactory.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

contract ModuleFactoryMock is IModuleFactory {
    IBeacon private _beacon;

    uint public addressCounter;

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
