pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";

/**
 * @title DeployAndRegisterModule Deployment Script
 *
 * @dev Script to deploy and register new Module to the factory.
 *
 * @dev This script exists to easily perform the addition of a new module to a live deployment. BEFORE running it, the ModuleRegistry should be updated with the new module's metadata and its deployment details added to the deployImplementation() function
 *
 *
 * @author Inverter Network
 */

// TODO: Test!!!!

contract DeployAndRegisterModule is
    Script,
    ProtocolConstants,
    ModuleRegistry
{
    // ############### IMPORTANT ################
    // Fill this out before running the script
    // ############### IMPORTANT ################
    IModule_v1.Metadata new_module_metadata = IModule_v1.Metadata().copy(); // Reference here the new module's metadata stored in the ModuleRegistry
    adddress target_moduleFactory = address(0x0); // Reference here to the target deployed moduleFactory
    bytes constructor_args; // Reference here to the constructor args for the new module
    
    
    function run(
   ) external returns (address) {
        InverterBeacon_v1 beacon;
        address module_implementation,

        if ((metadata.majorVersion == 0 && metadata.minorVersion == 0 && metadata.patchVersion == 0)  || target_moduleFactory == address(0)) {
            revert("Please fill out the required data in the contract before running the script");
        }

        module_implementation =
            deployImplementation(new_module_metadata.title, constructor_args); 

        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.
            beacon = new InverterBeacon_v1(
                ModuleFactory_v1(moduleFactory).reverter(),
                deployer,
                new_module_metadata.majorVersion,
                module_implementation,
                new_module_metadata.minorVersion,
                new_module_metadata.patchVersion
            );

            // Register Metadata at the ModuleFactory_v1
            ModuleFactory_v1(moduleFactory).registerMetadata(new_module_metadata, beacon);
        }
        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log(
            "Deployment of InverterBeacon_v1 for %s at address %s",
            new_module_metadata.title,
            address(beacon)
        );
        console2.log("Implementation upgraded and Metadata registered");

        return address(beacon);
    }
}
