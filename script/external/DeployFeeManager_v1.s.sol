pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {FeeManager_v1} from "@ex/fees/FeeManager_v1.sol";

/**
 * @title FeeManager Deployment Script
 *
 * @dev Script to deploy a new FeeManager and link it to a beacon.
 *
 * @author Inverter Network
 */
contract DeployFeeManager_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    function run() external returns (address) {
        // Read deployment settings from environment variables.

        address governor = vm.envAddress("GOVERNOR_ADDRESS");
        address defaultProtocolTreasury =
            vm.envAddress("COMMUNITY_MULTISIG_ADDRESS"); // Community Multisig as default treasury
        uint defaultCollateralFee = 100; // Should be 1%
        uint defaultIssuanceFee = 100; // Should be 1%
        // Check settings.

        require(
            governor != address(0),
            "DeployFeeManager: Missing env variable: governor"
        );

        require(
            defaultProtocolTreasury != address(0),
            "DeployFeeManager: Missing env variable: defaultProtocolTreasury"
        );

        // Deploy the Governor.
        return run(
            governor,
            defaultProtocolTreasury,
            defaultCollateralFee,
            defaultIssuanceFee
        );
    }

    /// @notice Creates the implementation of the FeeManager
    /// @return implementation The implementation of the FeeManager
    function run(
        address owner,
        address defaultProtocolTreasury,
        uint defaultCollateralFee,
        uint defaultIssuanceFee
    ) public returns (address implementation) {
        vm.startBroadcast(deployerPrivateKey);
        {
            FeeManager_v1 feeMan = new FeeManager_v1();

            feeMan.init(
                owner,
                defaultProtocolTreasury,
                defaultCollateralFee,
                defaultIssuanceFee
            );

            implementation = address(feeMan);
        }
        vm.stopBroadcast();

        // Log
        console2.log(
            "Deployment of Fee Manager implementation at address ",
            implementation
        );
    }
}
