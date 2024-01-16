// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {ScriptConstants} from "../script-constants.sol";

contract giveBountyManagerRoles is Script {
    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    // ===============================================================================================================
    // Introduce corresponding bounty manager and user addresses here
    // ===============================================================================================================
    address bountyManagerAddress =
        address(0xc24f66A74967c336c8Cd529308c193b05Ac3e02f);
    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    function run() public {
        address beneficiary =
            address(0x5AeeA3DF830529a61695A63ba020F01191E0aECb);

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
