// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {ScriptConstants} from "../script-constants.sol";

contract addClaim is Script {
    ScriptConstants scriptConstants = new ScriptConstants();
    uint orchestratorOwnerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    // ===============================================================================================================
    // Introduce corresponding bounty manager and user addresses here
    // ===============================================================================================================
    address bountyManagerAddress = scriptConstants.bountyManagerAddress();
    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    address user1 = scriptConstants.addBountyManagerClaim_user1();
    address user2 = scriptConstants.addBountyManagerClaim_user2();

    function run() public {
        IBountyManager.Contributor[] memory contributors =
            new IBountyManager.Contributor[](2);
        contributors[0] = IBountyManager.Contributor({
            addr: user1,
            claimAmount: scriptConstants.addBountyManagerClaim_user1_amount()
        });
        contributors[1] = IBountyManager.Contributor({
            addr: user2,
            claimAmount: scriptConstants.addBountyManagerClaim_user2_amount()
        });

        vm.startBroadcast(orchestratorOwner);

        uint claimId = bountyManager.addClaim(
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
