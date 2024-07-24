pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

/**
 * @title InverterBeacon_v1 Upgrade Script
 *
 * @dev Script to upgrade implementation in an existing beacon and update version
 *
 * @author Inverter Network
 */
contract UpgradeInverterBeacon_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    function run(
        address beacon,
        address implementation,
        uint minorVersion,
        uint patchVersion,
        bool overrideShutdown
    ) external {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Upgrade the Beacon to the chosen implementation
            InverterBeacon_v1(beacon).upgradeTo(
                address(implementation),
                minorVersion,
                patchVersion,
                overrideShutdown
            );
        }

        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log(
            "Implementation for Inverter Beacon at %s upgraded to %s",
            address(beacon),
            address(implementation)
        );
    }
}
