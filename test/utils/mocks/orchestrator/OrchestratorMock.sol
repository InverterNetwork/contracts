// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Orchestrator} from "src/orchestrator/Orchestrator.sol";

contract OrchestratorMock is Orchestrator {
    bool connectToTrustedForwarder = false;

    constructor(address _trustedForwarder) Orchestrator(_trustedForwarder) {}

    function flipConnectToTrustedForwarder() external {
        connectToTrustedForwarder = !connectToTrustedForwarder;
    }

    function isTrustedForwarder(address _forwarder)
        public
        view
        virtual
        override(Orchestrator)
        returns (bool)
    {
        if (connectToTrustedForwarder) {
            return super.isTrustedForwarder(_forwarder);
        } else {
            return false;
        }
    }
}
