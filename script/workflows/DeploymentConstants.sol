// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
This file contains constants for existing deployments on different chains.

The addresses stored here are the ones that should be called directly by the scripts (i.e. the proxies). To keep this file manageable, it sohuld only sotre the most important "high level" addresses. More specific addresses (i.e. the Becon for a specific module) should be found inside the scripts that need them.

Each deployment is stored as a struct.


*/

contract DeploymentConstants {
    struct DeploymentDetails {
        // Factory Addresses
        address orchestratorFactory;
        address moduleFactory;
        // Protocol level addresses
        address protocol_Reverter;
        address protocol_Governor;
        address protocol_FeeManager;
        address protocol_Treasury;
        address protocol_Forwarder;
        // Module dependencies
        address bancorFormula;
        address umaOptimisticOracleV3;
        address mockERC20; // Testnet only
    }

    // =============================================================================
    // Existing Deployments
    // =============================================================================

    /*
    // Deployment Details mainnet_constants  = new DeploymentDetails({
        orchestratorFactory = 0x...,
        moduleFactory = 0x...,
        etc.   

    });

    */
}
