// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";

contract ModuleMock is Module {
    function init(IProposal proposal_, Metadata memory data)
        external
        initializer
    {
        __Module_init(proposal_, data);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(IProposal proposal_, Metadata memory data)
        external
    {
        __Module_init(proposal_, data);
    }
}
