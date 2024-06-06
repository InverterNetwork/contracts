pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    ModuleFactory_v1, IModule_v1
} from "src/factories/ModuleFactory_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";

/**
 * @title ModuleFactory_v1 Deployment Script
 *
 * @dev Script to deploy a new ModuleFactory_v1.
 *
 *
 * @author Inverter Network
 */
contract DeployModuleFactory_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    ModuleFactory_v1 moduleFactory;
    DeployAndSetUpInverterBeacon_v1 deployAndSetUpInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();

    function run() external returns (address) {
        // Read deployment settings from environment variables.

        address governor = vm.envAddress("GOVERNOR_ADDRESS");
        address forwarder = vm.envAddress("FORWARDER_ADDRESS");
        // Check settings.

        require(
            governor != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: governor contract"
        );

        require(
            forwarder != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: forwarder"
        );

        // Deploy the moduleFactory.
        return run(
            governor,
            forwarder,
            new IModule_v1.Metadata[](0),
            new IInverterBeacon_v1[](0)
        );
    }

    function run(
        address governor,
        address forwarder,
        IModule_v1.Metadata[] memory initialMetadataRegistration,
        IInverterBeacon_v1[] memory initialBeaconRegistration
    ) public returns (address) {
        address moduleFactoryImplementation;
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the moduleFactory.
            moduleFactoryImplementation =
                address(new ModuleFactory_v1(forwarder));
        }
        vm.stopBroadcast();

        address moduleFactoryBeacon;
        address moduleFactoryProxy;

        (moduleFactoryBeacon, moduleFactoryProxy) =
        deployAndSetUpInverterBeacon_v1.deployBeaconAndSetupProxy(
            governor, moduleFactoryImplementation, 1, 0
        );

        moduleFactory = ModuleFactory_v1(moduleFactoryProxy);

        vm.startBroadcast(deployerPrivateKey);
        {
            moduleFactory.init(
                governor, initialMetadataRegistration, initialBeaconRegistration
            );
        }
        vm.stopBroadcast();

        // Log the deployed ModuleFactory_v1 contract address.
        console2.log(
            "Deployment of ModuleFactory_v1 at address", address(moduleFactory)
        );

        return address(moduleFactory);
    }
}
