// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {ScriptConstants} from "../script-constants.sol";

contract giveBountyManagerRoles is Script {
    // ==============================================================================================================
    // NOTE: This script is intended to give bounty manager roles to a specific address.
    //       The address of the specific BountyManager or beneficiary should be specified in the enivronment variables or can be edited into the script manually.
    // ==============================================================================================================

    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    address bountyManagerAddress =
        vm.envAddress("DEPLOYED_BOUNTY_MANAGER_ADDRESS"); // The exisiting Bounty Manager instance
    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    address beneficiary = vm.envAddress("ROLE_BENEFICIARY_ADDRESS"); // The address that will be granted the roles

    function run() public {
        vm.startBroadcast(orchestratorOwner);

        bountyManager.grantModuleRole(
            bountyManager.BOUNTY_ISSUER_ROLE(), beneficiary
        );
        bountyManager.grantModuleRole(
            bountyManager.CLAIMANT_ROLE(), beneficiary
        );
        bountyManager.grantModuleRole(
            bountyManager.VERIFIER_ROLE(), beneficiary
        );

        vm.stopBroadcast();

        console2.log(
            "=================================================================================="
        );
        console2.log("Done");
        console2.log(
            "=================================================================================="
        );
    }
}
