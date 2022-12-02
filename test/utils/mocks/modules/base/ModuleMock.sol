// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Module, IModule, IProposal} from "src/modules/base/Module.sol";

contract ModuleMock is Module {
    function init(IProposal proposal_, Metadata memory metadata, bytes memory)
        public
        virtual
        override (Module)
        initializer
    {
        __Module_init(proposal_, metadata);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory
    ) external {
        __Module_init(proposal_, metadata);
    }
}
