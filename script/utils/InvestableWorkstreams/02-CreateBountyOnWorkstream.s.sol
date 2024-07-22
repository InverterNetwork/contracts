// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../../deployment/DeploymentScript.s.sol";

import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {
    LM_PC_Bounties_v1, ILM_PC_Bounties_v1
} from "@lm/LM_PC_Bounties_v1.sol";

// import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
// import {ScriptConstants} from "../script-constants.sol";

contract CreateBountyInWorkstream is Script {
    // ========================================================================
    // ENVIRONMENT VARIABLES OR CONSTANTS

    address deployedOrchestratorAddress =
        vm.envAddress("DEPLOYED_ORCHESTRATOR_ADDRESS");
    IOrchestrator_v1 _orchestrator =
        IOrchestrator_v1(deployedOrchestratorAddress);

    uint bountyCreatorPrivateKey = vm.envUint("BOUNTY_CREATOR_PRIVATE_KEY");
    address bountyCreator = vm.addr(bountyCreatorPrivateKey);

    // ========================================
    // BOUTNY DATA
    uint MINIMUM_BOUNTY_PAYOUT = 10e18;
    uint MAXIMUM_BOUNTY_PAYOUT = 25e18;
    bytes BOUNTY_DETAILS = "TEST BOUNTY";

    // ========================================

    function run() public {
        // Find LM_PC_Bounties_v1

        address[] memory moduleAddresses =
            IOrchestrator_v1(_orchestrator).listModules();
        uint lenModules = moduleAddresses.length;
        address orchestratorCreatedBountyManagerAddress;

        for (uint i; i < lenModules;) {
            try ILM_PC_Bounties_v1(moduleAddresses[i]).isExistingBountyId(0)
            returns (bool) {
                orchestratorCreatedBountyManagerAddress = moduleAddresses[i];
                break;
            } catch {
                i++;
            }
        }

        LM_PC_Bounties_v1 orchestratorCreatedBountyManager =
            LM_PC_Bounties_v1(orchestratorCreatedBountyManagerAddress);

        vm.startBroadcast(bountyCreatorPrivateKey);
        {
            orchestratorCreatedBountyManager.addBounty(
                MINIMUM_BOUNTY_PAYOUT, MAXIMUM_BOUNTY_PAYOUT, BOUNTY_DETAILS
            );
        }
    }
}
