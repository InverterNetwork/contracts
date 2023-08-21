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

    address bountyManagerAddress = 0x7560b724B90eD62bF1ab3D374CdaD6d14EAF09BB;
    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    function run() public {
        IBountyManager.Contributor[] memory contributors =
            new IBountyManager.Contributor[](2);
        contributors[0] = IBountyManager.Contributor({
            addr: 0x9518a55e5cd4Ac650A37a6Ab6c352A3146D2C9BD,
            claimAmount: 100_000_000_000_000_000_000
        });
        contributors[1] = IBountyManager.Contributor({
            addr: 0x3064A400b5e74BeA12391058930EfD95a6911970,
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
