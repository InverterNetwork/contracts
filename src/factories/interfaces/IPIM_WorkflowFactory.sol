// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    IModule_v1
} from "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IPIM_WorkflowFactory} from
    "src/factories/interfaces/IPIM_WorkflowFactory.sol";

interface IPIM_WorkflowFactory {
    struct IssuanceTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        uint maxSupply;
        address initialAdmin;
    }

    struct PIMConfig {
        IModule_v1.Metadata metadata;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
            bcProperties;
        IssuanceTokenParams issuanceTokenParams;
        address recipient;
        address collateralToken;
        bool isRenouncedIssuanceToken;
        bool isRenouncedWorkflow;
    }

    event PIMWorkflowCreated(address indexed issuanceToken);
    event FeeSet(uint fees);
}
