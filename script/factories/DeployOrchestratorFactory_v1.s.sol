pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";

import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";

/**
 * @title OrchestratorFactory_v1 Deployment Script
 *
 * @dev Script to deploy a new OrchestratorFactory_v1.
 *
 *      The implementation and moduleFactory_v1 addresses can be supplied directly or read from the following environment variables:
 *      - DEPLOYMENT_ORCHESTRATOR_FACTORY_ORCHESTRATOR_IMPLEMENTATION
 *      - DEPLOYMENT_ORCHESTRATOR_FACTORY_MODULE_FACTORY
 *
 * @author Inverter Network
 */
contract DeployOrchestratorFactory_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    OrchestratorFactory_v1 orchestratorFactory;

    DeployAndSetUpInverterBeacon_v1 deployAndSetUpInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();

    function run() external returns (address) {
        // Read deployment settings from environment variables.
        address orchestratorImplementation = vm.envAddress(
            "DEPLOYMENT_ORCHESTRATOR_FACTORY_ORCHESTRATOR_IMPLEMENTATION"
        );
        address moduleFactory =
            vm.envAddress("DEPLOYMENT_ORCHESTRATOR_FACTORY_MODULE_FACTORY");
        address governor = vm.envAddress("GOVERNOR_ADDRESS");
        address forwarder = vm.envAddress("FORWARDER_ADDRESS");
        // Check settings.
        require(
            orchestratorImplementation != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: orchestratorImplementation"
        );
        require(
            moduleFactory != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: moduleFactory"
        );
        require(
            governor != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: governor contract"
        );
        require(
            forwarder != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: forwarder"
        );

        // Deploy the orchestratorFactory.
        return
            run(governor, orchestratorImplementation, moduleFactory, forwarder);
    }

    function run(
        address governor,
        address orchestratorImplementation,
        address moduleFactory,
        address forwarder
    ) public returns (address) {
        address orchestratorFactoryImplementation;
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the moduleFactory.
            orchestratorFactoryImplementation =
                address(new OrchestratorFactory_v1(forwarder));
        }
        vm.stopBroadcast();

        address orchestratorFactoryBeacon;
        address orchestratorFactoryProxy;

        (orchestratorFactoryBeacon, orchestratorFactoryProxy) =
        deployAndSetUpInverterBeacon_v1.deployBeaconAndSetupProxy(
            governor,
            orchestratorFactoryImplementation,
            1,
            0 //@note do we have a way to smartly track these Versions?
        );

        address orchestratorImplementationBeacon =
        deployAndSetUpInverterBeacon_v1.deployInverterBeacon(
            governor, orchestratorImplementation, 1, 0
        );

        orchestratorFactory = OrchestratorFactory_v1(orchestratorFactoryProxy);

        vm.startBroadcast(deployerPrivateKey);
        {
            orchestratorFactory.init(
                governor,
                IInverterBeacon_v1(orchestratorImplementationBeacon),
                moduleFactory
            );
        }
        vm.stopBroadcast();

        // Log the deployed OrchestratorFactory_v1 contract address.
        console2.log(
            "Deployment of OrchestratorFactory_v1 at address",
            address(orchestratorFactory)
        );

        return address(orchestratorFactory);
    }
}
