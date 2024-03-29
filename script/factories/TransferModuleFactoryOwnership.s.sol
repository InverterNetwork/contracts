pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";

/**
 * @title ModuleFactory Ownership Transfer Script
 *
 * @dev Script to transfer the ownership of an existing ModuleFactory.
 *
 *
 * @author Inverter Network
 */
contract TransferModuleFactoryOwnership is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address governance = vm.envAddress("GOVERNANCE_CONTRACT_ADDRESS");

    function run(address moduleFactory, address _newOwner) external {
        address newOwner = _newOwner != address(0) ? _newOwner : governance;

        vm.startBroadcast(deployerPrivateKey);
        {
            ModuleFactory(moduleFactory).transferOwnership(newOwner);
        }

        require(
            ModuleFactory(moduleFactory).pendingOwner() == newOwner,
            "Ownership Transfer Initiation failed."
        );

        vm.stopBroadcast();

        console2.log(
            "Ownership of ModuleFactory %s transferred to %s. (New Owner needs to accept!)",
            moduleFactory,
            newOwner
        );
    }
}
