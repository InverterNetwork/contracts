// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Orchestrator} from "src/orchestrator/Orchestrator.sol";

contract OrchestratorMock is Orchestrator {
    bool connectToTrustedForwarder = false;
    bool public interceptData;
    bool public executeTxBoolReturn;
    bytes public executeTxData;

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

    function executeTxFromModule(address to, bytes memory data)
        external
        override(IModuleManager, ModuleManager)
        onlyModule
        returns (bool, bytes memory)
    {
        if (interceptData) {
            executeTxData = data;
            return (executeTxBoolReturn, bytes(""));
        } else {
            bool ok;
            bytes memory returnData;

            (ok, returnData) = to.call(data);

            return (ok, returnData);
        }
    }

    function setInterceptData(bool b) external {
        interceptData = b;
    }

    function setExecuteTxBoolReturn(
        bool boo //<--- this is a scary function
    ) external {
        executeTxBoolReturn = boo;
    }
}
