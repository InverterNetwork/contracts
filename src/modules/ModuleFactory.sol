// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";

// Interfaces
import {IModule} from "src/interfaces/IModule.sol";

contract ModuleFactory {
    mapping(bytes32 => address) private _moduleIdToImplementation;

    constructor() {}

    // @todo mp: Need owner.

    function addModule(bytes32 id, address implementation) external {
        // @todo mp: Add checks + onlyOwner.
        _moduleIdToImplementation[id] = implementation;
    }

    // @todo mp: Maybe onlyProposalFactory?
    //           Then we could use the same salt and use create2.
    function createModule(bytes32 id, bytes memory data)
        external
        returns (address)
    {
        address implementation = _moduleIdToImplementation[id];
        // @todo mp: Add checks.

        address clone = Clones.clone(implementation);

        // @todo mp: IModule does not have initialize func yet.
        // IModule(clone).initialize(data);

        return clone;
    }
}
