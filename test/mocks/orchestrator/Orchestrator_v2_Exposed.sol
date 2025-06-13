// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Orchestrator_v2} from "src/orchestrator/Orchestrator_v2.sol";

import {ModuleManagerBase_v1} from
    "src/orchestrator/abstracts/ModuleManagerBase_v1.sol";

import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";

contract Orchestrator_v2_Exposed is Orchestrator_v2 {
    //==========================================================================
    // Setup
    constructor(address _trustedForwarder) Orchestrator_v2(_trustedForwarder) {}

    function setup_authorizer(address authorizer_) external {
        authorizer = IAuthorizer_v2(authorizer_);
    }

    //==========================================================================
    // Modifier Access

    function modifierPermissionedCheck() external view permissioned {}

    //==========================================================================
    // Internal Function Access

    function _checkAuthorization_exposed(address caller_, bytes calldata data_)
        external
        view
    {
        _checkAuthorization(caller_, data_);
    }
}
