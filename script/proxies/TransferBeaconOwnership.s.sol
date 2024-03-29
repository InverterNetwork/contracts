pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";

/**
 * @title Beacon Ownership Transfer Script
 *
 * @dev Script to transfer the ownership of an existing beacon
 *
 * @author Inverter Network
 */
contract TransferBeaconOwnership is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address governance = vm.envAddress("GOVERNANCE_CONTRACT_ADDRESS");

    function run(address beacon, address _newOwner) external {
        address newOwner = _newOwner != address(0) ? _newOwner : governance;

        vm.startBroadcast(deployerPrivateKey);
        {
            InverterBeacon(beacon).transferOwnership(newOwner);
        }

        require(
            InverterBeacon(beacon).pendingOwner() == newOwner,
            "Ownership Transfer Initiation failed."
        );

        vm.stopBroadcast();

        console2.log(
            "Ownership of Beacon %s transferred to %s. (New Owner needs to accept!)",
            beacon,
            newOwner
        );
    }
}
