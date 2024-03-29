pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";

/**
 * @title RecurringPaymentManager Deployment Script
 *
 * @dev Script to deploy a new RecurringPaymentManager.
 *
 *
 * @author Inverter Network
 */
contract DeployRecurringPaymentManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    RecurringPaymentManager recurringPaymentManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the recurringPaymentManager.

            recurringPaymentManager = new RecurringPaymentManager();
        }

        vm.stopBroadcast();

        // Log the deployed RecurringPaymentManager contract address.
        console2.log(
            "Deployment of RecurringPaymentManager Implementation at address",
            address(recurringPaymentManager)
        );

        return address(recurringPaymentManager);
    }
}
