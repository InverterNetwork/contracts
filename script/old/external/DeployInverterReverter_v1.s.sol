pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterReverter_v1} from
    "src/external/reverter/InverterReverter_v1.sol";

/**
 * @title TransactionForwarder_v1 Deployment Script
 *
 * @dev Script to deploy a new TransactionForwarder_v1 and link it to a beacon.
 *
 * @author Inverter Network
 */
contract DeployInverterReverter_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    /// @notice Creates the implementation of the InverterReverter_v1
    /// @return implementation The implementation of the InverterReverter_v1
    function run() external returns (address implementation) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the transaction forwarder.
            implementation = address(new InverterReverter_v1());
        }
        vm.stopBroadcast();

        // Log
        console2.log(
            "Deployment of InverterReverter_v1 implementation at address ",
            implementation
        );
    }
}
