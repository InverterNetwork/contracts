// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Orchestrator} from "src/orchestrator/Orchestrator.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {
    IModuleManager,
    ModuleManager
} from "src/orchestrator/base/ModuleManager.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

contract OrchestratorMock is Orchestrator {
    bool public interceptData;
    bool public executeTxBoolReturn;
    bytes public executeTxData;

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
