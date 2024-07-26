// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ModuleRegistry} from "script/ModuleRegistry.sol";

// Import interfaces:

import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

import {Governor_v1} from "@ex/governance/Governor_v1.sol";
import {FeeManager_v1} from "@ex/fees/FeeManager_v1.sol";

// Import scripts:
import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";

contract MainnetDeploymentScript is ModuleRegistry {
    /// @notice Deploys all necessary factories, beacons and implementations, plus necessary periphery contracts for testnets
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual override returns (address factory) {
        factory = super.run();

        //============================================================================
        // Necessary Periphery Contracts
        //============================================================================

        // General
        // iUSD

        // FM_BC_Bancor_
        // BancorFormula

        // KPI Rewarder
        // OptimisticOracleV3Mock

        return factory;
    }
}
