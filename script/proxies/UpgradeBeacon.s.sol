pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Beacon} from "src/factories/beacon/Beacon.sol";
import {IModule} from "src/modules/base/IModule.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {DeployBeacon} from "script/proxies/DeployBeacon.s.sol";

/**
 * @title Beacon Deployment Script
 *
 * @dev Script to upgrade implementation in an existing beacon and update metadata.
 *
 *
 * @author Inverter Network
 */
contract UpgradeBeacon is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    Beacon beacon;

    function run() external returns (address) {
        address implementation = 0x5c335736fD2ec911C56803C75401BecBDd6Ba6E0;
        address moduleFactory = 0x349D52589aF62Ba1b35DB871F54FA2c5aFcA6B5B;
        IModule.Metadata memory metadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/funding-manager",
            "RebasingFundingManager"
        );

        return run(implementation, moduleFactory, metadata);
    }

    function run(
        address implementation,
        address moduleFactory,
        IModule.Metadata memory metadata
    ) public returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.
            //beacon = new Beacon();
            beacon = Beacon(0xe8F706F0C55212ef1A5781204C3a36ef6E4Ec92F);

            // Upgrade the Beacon to the chosen implementation
            beacon.upgradeTo(address(implementation));

            // Register Metadata at the ModuleFactory
            ModuleFactory(moduleFactory).registerMetadata(
                metadata, Beacon(beacon)
            );
        }
        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log("Deployment of Beacon at address", address(beacon));
        console2.log("Implementation upgraded an Metadata registered");

        return address(beacon);
    }
}
