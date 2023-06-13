pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Beacon} from "src/factories/beacon/Beacon.sol";
import {IModule} from "src/modules/base/IModule.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {DeployBeacon} from "script/proxies/DeployBeacon.s.sol";

/**
 * @title Beacon Deployment Script
 *
 * @dev Script to deploy a new Beacon.
 *
 *
 * @author Inverter Network
 */

contract DeployAndSetUpBeacon is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    Beacon beacon;

    function run(
        address implementation,
        address moduleFactory,
        IModule.Metadata calldata metadata
    ) external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.
            beacon = new Beacon();

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
