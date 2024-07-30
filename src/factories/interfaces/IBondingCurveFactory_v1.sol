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
import {IBondingCurveFactory_v1} from
    "src/factories/interfaces/IBondingCurveFactory_v1.sol";

interface IBondingCurveFactory_v1 {
    struct IssuanceTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        uint maxSupply;
        address initialAdmin;
    }

    struct LaunchConfig {
        IModule_v1.Metadata metadata;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
            bcProperties;
        IssuanceTokenParams issuanceTokenParams;
        address recipient;
        address collateralToken;
        bool isRenouncedIssuanceToken;
        bool isRenouncedWorkflow;
    }

    event BcPimCreated(address indexed issuanceToken);
    event FeeSet(uint fees);
}
