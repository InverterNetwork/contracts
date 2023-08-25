// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";

contract addClaim is Script {
    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    // ===============================================================================================================
    // Introduce corresponding bounty manager and user addresses here
    // ===============================================================================================================
    address bountyManagerAddress = 0x4FB5adc63fB08c7E7864Ce3f77714af6B8B50D9f;
    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    address user1 = 0x9518a55e5cd4Ac650A37a6Ab6c352A3146D2C9BD;
    address user2 = 0x3064A400b5e74BeA12391058930EfD95a6911970;

    function run() public {
        IBountyManager.Contributor[] memory contributors =
            new IBountyManager.Contributor[](2);
        contributors[0] = IBountyManager.Contributor({
            addr: user1,
            claimAmount: 100_000_000_000_000_000_000
        });
        contributors[1] = IBountyManager.Contributor({
            addr: user2,
            claimAmount: 100_000_000_000_000_000_000
        });

        vm.startBroadcast(orchestratorOwner);

        uint claimId = bountyManager.addClaim(1, contributors, "0x0");

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
