pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {LM_PC_KPIRewarder_v1} from "@lm/LM_PC_KPIRewarder_v1.sol";
/**
 * @title DeployLM_PC_KPIRewarder_v1 Deployment Script
 *
 * @dev Script to deploy a new LM_PC_KPIRewarder_v1.
 *
 *
 * @author Inverter Network
 */

contract DeployLM_PC_KPIRewarder_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    LM_PC_KPIRewarder_v1 kpiRewarder;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the kpiRewarder.
            kpiRewarder = new LM_PC_KPIRewarder_v1();
        }
        vm.stopBroadcast();
        // Log the deployed KPI Rewarder contract address.
        console2.log(
            "Deployment of KPI Rewarder Implementation at address",
            address(kpiRewarder)
        );
        return address(kpiRewarder);
    }
}
