pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";

/**
 * @title Beacon Upgrade Script
 *
 * @dev Script to upgrade implementation in an existing beacon and update version
 *
 * @author Inverter Network
 */
contract UpgradeBeacon is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    function run(
        address beacon,
        address implementation,
        uint minorVersion,
        bool overrideShutdown
    ) external {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Upgrade the Beacon to the chosen implementation
            InverterBeacon(beacon).upgradeTo(
                address(implementation), minorVersion, overrideShutdown
            );
        }

        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log("Implementation upgraded at address", address(beacon));
    }
}
