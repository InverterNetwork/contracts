// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    LM_PC_Bounties_v1, ILM_PC_Bounties_v1
} from "@lm/LM_PC_Bounties_v1.sol";
import {ScriptConstants} from "../script-constants.sol";

contract giveBountyManagerRoles is Script {
    // ==============================================================================================================
    // NOTE: This script is intended to give bounty manager roles to a specific address.
    //       The address of the specific LM_PC_Bounties_v1 or beneficiary should be specified in the enivronment variables or can be edited into the script manually.
    // ==============================================================================================================

    uint orchestratorAdminPrivateKey =
        vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address orchestratorAdmin = vm.addr(orchestratorAdminPrivateKey);

    address bountyManagerAddress =
        vm.envAddress("DEPLOYED_BOUNTY_MANAGER_ADDRESS"); // The exisiting Bounty Manager instance
    LM_PC_Bounties_v1 LM_PC_Bounties_v1_Implementation =
        LM_PC_Bounties_v1(bountyManagerAddress);

    address beneficiary = vm.envAddress("ROLE_BENEFICIARY_ADDRESS"); // The address that will be granted the roles

    function run() public {
        vm.startBroadcast(orchestratorAdmin);

        LM_PC_Bounties_v1_Implementation.grantModuleRole(
            LM_PC_Bounties_v1_Implementation.BOUNTY_ISSUER_ROLE(), beneficiary
        );
        LM_PC_Bounties_v1_Implementation.grantModuleRole(
            LM_PC_Bounties_v1_Implementation.CLAIMANT_ROLE(), beneficiary
        );
        LM_PC_Bounties_v1_Implementation.grantModuleRole(
            LM_PC_Bounties_v1_Implementation.VERIFIER_ROLE(), beneficiary
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
