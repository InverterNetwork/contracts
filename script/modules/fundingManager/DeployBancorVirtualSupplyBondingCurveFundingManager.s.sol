pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1} from
    "src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.sol";

/**
 * @title FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1 Deployment Script
 *
 * @dev Script to deploy a new FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.
 *
 * @author Inverter Network
 */
contract DeployBancorVirtualSupplyBondingCurveFundingManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1 fundingManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.

            fundingManager = new FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1(
            );
        }

        vm.stopBroadcast();
        // Log the deployed FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1 contract address.
        console2.log(
            "Deployment of FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1 Implementation at address: ",
            address(fundingManager)
        );

        return address(fundingManager);
    }
}
