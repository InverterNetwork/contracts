// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    ModuleManagerBase_v1,
    IModuleManagerBase_v1
} from "src/orchestrator/abstracts/ModuleManagerBase_v1.sol";
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

contract OrchestratorV1Mock is Orchestrator_v1 {
    bool connectToTrustedForwarder = false;
    bool public interceptData;

    constructor(address _trustedForwarder) Orchestrator_v1(_trustedForwarder) {}

    function flipConnectToTrustedForwarder() external {
        connectToTrustedForwarder = !connectToTrustedForwarder;
    }

    function isTrustedForwarder(address _forwarder)
        public
        view
        virtual
        override(Orchestrator_v1)
        returns (bool)
    {
        if (connectToTrustedForwarder) {
            return super.isTrustedForwarder(_forwarder);
        } else {
            return false;
        }
    }

    function setInterceptData(bool b) external {
        interceptData = b;
    }
}
