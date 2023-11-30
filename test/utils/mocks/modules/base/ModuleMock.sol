// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Module, IModule, IOrchestrator} from "src/modules/base/Module.sol";

contract ModuleMock is Module {
    constructor() Module(address(0)) {}

    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) public virtual override(Module) initializer {
        __Module_init(orchestrator_, metadata);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) external {
        __Module_init(orchestrator_, metadata);
    }
}
