// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModuleFactory} from "src/interfaces/IModuleFactory.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

contract ModuleFactoryMock is IModuleFactory {
    address private _target;

    uint public addressCounter;

    function createModule(IModule.Metadata memory, IProposal, bytes memory)
        external
        returns (address)
    {
        return address(uint160(++addressCounter));
    }

    function target(IModule.Metadata memory) external view returns (address) {
        return _target;
    }

    function registerMetadata(IModule.Metadata memory, address) external {}
}
