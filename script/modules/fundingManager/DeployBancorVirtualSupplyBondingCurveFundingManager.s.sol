pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {BancorVirtualSupplyBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";

/**
 * @title BancorVirtualSupplyBondingCurveFundingManager Deployment Script
 *
 * @dev Script to deploy a new BancorVirtualSupplyBondingCurveFundingManager.
 *
 * @author Inverter Network
 */
contract DeployBancorVirtualSupplyBondingCurveFundingManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    BancorVirtualSupplyBondingCurveFundingManager fundingManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the BancorVirtualSupplyBondingCurveFundingManager.

            fundingManager = new BancorVirtualSupplyBondingCurveFundingManager();
        }

        vm.stopBroadcast();
        // Log the deployed BancorVirtualSupplyBondingCurveFundingManager contract address.
        console2.log(
            "Deployment of BancorVirtualSupplyBondingCurveFundingManager Implementation at address: ",
            address(fundingManager)
        );

        return address(fundingManager);
    }
}
