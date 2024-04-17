// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Module, IModule, IOrchestrator_v1} from "src/modules/base/Module.sol";

contract ModuleMock is Module {
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) public virtual override(Module) initializer {
        __Module_init(orchestrator_, metadata);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) external {
        __Module_init(orchestrator_, metadata);
    }

    function original_msgSender()
        external
        view
        virtual
        returns (address sender)
    {
        return _msgSender();
    }

    function original_msgData()
        external
        view
        virtual
        returns (bytes calldata)
    {
        return _msgData();
    }
}
