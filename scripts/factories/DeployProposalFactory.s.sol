pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {ProposalFactory} from "src/factories/ProposalFactory.sol";

/**
 * @title ProposalFactory Deployment Script
 *
 * @dev Script to deploy a new ProposalFactory.
 *
 *      The following environment variables MUST be provided:
 *      - DEPLOYMENT_PROPOSAL_FACTORY_TARGET
 *      - DEPLOYMENT_PROPOSAL_FACTORY_MODULE_FACTORY
 *
 * @author byterocket
 */

contract DeployProposalFactory is Script {

    ProposalFactory proposalFactory;

    function run() external {

        // Read deployment settings from environment variables.
        address target
            = vm.envAddress("DEPLOYMENT_PROPOSAL_FACTORY_TARGET");
        address moduleFactory
            = vm.envAddress("DEPLOYMENT_PROPOSAL_FACTORY_MODULE_FACTORY");

        // Check settings.
        require(target != address(0),
            "DeployProposalFactory: Missing env variable: target");
        require(moduleFactory != address(0),
            "DeployProposalFactory: Missing env variable: moduleFactory");

        // Deploy the proposalFactory.
        vm.startBroadcast();
        {
            proposalFactory = new ProposalFactory(target, moduleFactory);
        }
        vm.stopBroadcast();

        // Log the deployed ProposalFactory contract address.
        console2.log("Deployment of ProposalFactory at address",
            address(proposalFactory));
    }

}
