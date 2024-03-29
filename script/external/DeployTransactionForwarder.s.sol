pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";
import {InverterBeaconProxy} from "src/factories/beacon/InverterBeaconProxy.sol";
import {TransactionForwarder} from
    "src/external/forwarder/TransactionForwarder.sol";

/**
 * @title TransactionForwarder Deployment Script
 *
 * @dev Script to deploy a new TransactionForwarder and link it to a beacon.
 *
 * @author Inverter Network
 */
contract DeployTransactionForwarder is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    /// @notice Creates the implementation, beacon and proxy of the transactionForwarder
    /// @return implementation The implementation of the TransactionForwarder that will be referenced in the beacon
    function run() external returns (address implementation) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the transaction forwarder.
            implementation = address(
                new TransactionForwarder("Inverter Transaction Forwarder")
            );
        }
        vm.stopBroadcast();

        // Log
        console2.log(
            "Deployment of Transaction Forwarder implementation at address ",
            implementation
        );
    }
}
