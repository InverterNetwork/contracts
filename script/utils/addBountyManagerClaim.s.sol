// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    LM_PC_Bounties_v1, ILM_PC_Bounties_v1
} from "@lm/LM_PC_Bounties_v1.sol";
import {ScriptConstants} from "../script-constants.sol";

contract addClaim is Script {
    ScriptConstants scriptConstants = new ScriptConstants();
    uint orchestratorAdminPrivateKey =
        vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address orchestratorAdmin = vm.addr(orchestratorAdminPrivateKey);

    // ===============================================================================================================
    // Introduce corresponding bounty manager and user addresses here
    // ===============================================================================================================
    address bountyManagerAddress = scriptConstants.bountyManagerAddress();
    LM_PC_Bounties_v1 LM_PC_Bounties_v1_Implementation =
        LM_PC_Bounties_v1(bountyManagerAddress);

    address user1 = scriptConstants.addBountyManagerClaim_user1();
    address user2 = scriptConstants.addBountyManagerClaim_user2();

    function run() public {
        ILM_PC_Bounties_v1.Contributor[] memory contributors =
            new ILM_PC_Bounties_v1.Contributor[](2);
        contributors[0] = ILM_PC_Bounties_v1.Contributor({
            addr: user1,
            claimAmount: scriptConstants.addBountyManagerClaim_user1_amount()
        });
        contributors[1] = ILM_PC_Bounties_v1.Contributor({
            addr: user2,
            claimAmount: scriptConstants.addBountyManagerClaim_user2_amount()
        });

        vm.startBroadcast(orchestratorAdmin);

        uint claimId = LM_PC_Bounties_v1_Implementation.addClaim(
            1, contributors, scriptConstants.emptyBytes()
        );

        vm.stopBroadcast();

        console2.log(
            "=================================================================================="
        );
        console2.log("Claim added with id: ", claimId);
        console2.log(
            "=================================================================================="
        );
    }
}
