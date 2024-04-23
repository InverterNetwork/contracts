pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";
import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";

/**
 * @title TransactionForwarder_v1 Deployment Script
 *
 * @dev Script to deploy a new TransactionForwarder_v1 and link it to a beacon.
 *
 * @author Inverter Network
 */
contract DeployTransactionForwarder_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    /// @notice Creates the implementation, beacon and proxy of the transactionForwarder
    /// @return implementation The implementation of the TransactionForwarder_v1 that will be referenced in the beacon
    function run() external returns (address implementation) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the transaction forwarder.
            implementation = address(
                new TransactionForwarder_v1("Inverter Transaction Forwarder")
            );
        }
        vm.stopBroadcast();

        // Log
        console2.log(
            "Deployment of TransactionForwarder_v1 implementation at address ",
            implementation
        );
    }
}
