// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";
import {Orchestrator_v2} from "src/orchestrator/Orchestrator_v2.sol";

contract Orchestrator_v2Mock is Orchestrator_v2 {
    IAuthorizer_v2 newAuthorizer;

    constructor(address) Orchestrator_v2(address(0)) {}

    function overrideSetAuthorizer(IAuthorizer_v2 newAuthorizer_) external {
        authorizer = newAuthorizer_;
    }
}
