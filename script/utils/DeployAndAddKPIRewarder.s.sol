pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {LM_PC_KPIRewarder_v1} from "@lm/LM_PC_KPIRewarder_v1.sol";

import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
/**
 * @title DeployLM_PC_KPIRewarder_v1 Deployment Script
 *
 * @dev Script to deploy a new LM_PC_KPIRewarder_v1.
 *
 *
 * @author Inverter Network
 */

contract DeployKPIRewarder is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    LM_PC_KPIRewarder_v1 kpiRewarder;
    //Beacon
    DeployAndSetUpInverterBeacon_v1 deployAndSetupInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();
    address moduleFactory = 0x1b852726489a43645C4414aC59171AB48be23D57; // current sepolia factory address
    IModule_v1.Metadata kpiRewarderMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_KPIRewarder_v1"
    );

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the KPIRewarder_v1.
            kpiRewarder = new LM_PC_KPIRewarder_v1();
        }
        vm.stopBroadcast();
        // Log the deployed KPIRewarder_v1 contract address.
        console2.log(
            "Deployment of KPIRewarder_v1 Implementation at address",
            address(kpiRewarder)
        );
        address kpiRewarderBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            deployer, address(kpiRewarder), moduleFactory, kpiRewarderMetadata
        );
        return address(kpiRewarder);
    }
}
