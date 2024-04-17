// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../../deployment/DeploymentScript.s.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator} from "src/orchestrator/Orchestrator.sol";
import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

//import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
//import {ScriptConstants} from "../script-constants.sol";

contract CreateBountyInWorkstream is Script {
    // ========================================================================
    // ENVIRONMENT VARIABLES OR CONSTANTS

    address deployedOrchestratorAddress =
        vm.envAddress("DEPLOYED_ORCHESTRATOR_ADDRESS");
    IOrchestrator _orchestrator = IOrchestrator(deployedOrchestratorAddress);

    uint bountyCreatorPrivateKey = vm.envUint("BOUNTY_CREATOR_PRIVATE_KEY");
    address bountyCreator = vm.addr(bountyCreatorPrivateKey);

    // ========================================
    // BOUTNY DATA
    uint MINIMUM_BOUNTY_PAYOUT = 10e18;
    uint MAXIMUM_BOUNTY_PAYOUT = 25e18;
    bytes BOUNTY_DETAILS = "TEST BOUNTY";

    // ========================================

    function run() public {
        // Find BountyManager

        address[] memory moduleAddresses =
            IOrchestrator(_orchestrator).listModules();
        uint lenModules = moduleAddresses.length;
        address orchestratorCreatedBountyManagerAddress;

        for (uint i; i < lenModules;) {
            try IBountyManager(moduleAddresses[i]).isExistingBountyId(0)
            returns (bool) {
                orchestratorCreatedBountyManagerAddress = moduleAddresses[i];
                break;
            } catch {
                i++;
            }
        }

        BountyManager orchestratorCreatedBountyManager =
            BountyManager(orchestratorCreatedBountyManagerAddress);

        vm.startBroadcast(bountyCreatorPrivateKey);
        {
            orchestratorCreatedBountyManager.addBounty(
                MINIMUM_BOUNTY_PAYOUT, MAXIMUM_BOUNTY_PAYOUT, BOUNTY_DETAILS
            );
        }
    }
}
