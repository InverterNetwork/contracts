pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ProposalFactory} from "src/factories/ProposalFactory.sol";

/**
 * @title ProposalFactory Deployment Script
 *
 * @dev Script to deploy a new ProposalFactory.
 *
 *      The implementation and moduleFactory addresses can be supplied directly or read from the following environment variables:
 *      - DEPLOYMENT_PROPOSAL_FACTORY_TARGET
 *      - DEPLOYMENT_PROPOSAL_FACTORY_MODULE_FACTORY
 *
 * @author byterocket
 */

contract DeployProposalFactory is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    ProposalFactory proposalFactory;

    function run() external returns (address) {
        // Read deployment settings from environment variables.
        address target = vm.envAddress("DEPLOYMENT_PROPOSAL_FACTORY_TARGET");
        address moduleFactory =
            vm.envAddress("DEPLOYMENT_PROPOSAL_FACTORY_MODULE_FACTORY");

        // Check settings.
        require(
            target != address(0),
            "DeployProposalFactory: Missing env variable: target"
        );
        require(
            moduleFactory != address(0),
            "DeployProposalFactory: Missing env variable: moduleFactory"
        );

        // Deploy the proposalFactory.
        return run(target, moduleFactory);
    }

    function run(address target, address moduleFactory)
        public
        returns (address)
    {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the proposalFactory.
            proposalFactory = new ProposalFactory(target, moduleFactory);
        }

        vm.stopBroadcast();

        // Log the deployed ProposalFactory contract address.
        console2.log(
            "Deployment of ProposalFactory at address", address(proposalFactory)
        );

        return address(proposalFactory);
    }
}
