// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

import {MilestoneManager} from "src/modules/MilestoneManager.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

/**
 * E2e test demonstrating how to add, start, and complete a Milestone.
 */
contract MilestoneLifecycle is E2eTest {
    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_MilestoneLifecycle() public {
        // First, we create a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        // Now we add a new milestone.
        // For that, we need to access the proposal's milestone module.
        // Note that we normally receive the proposal's module implementations
        // from the emitted events during the proposal creation.
        // However, in Solidity it is not possible to access events, so we
        // copied the module's (deterministic in this test) address from the
        // logs.
        MilestoneManager milestoneManager =
            MilestoneManager(0xa78f6C9322C3f1b396720945B6C3035A4a1B3d70);

        //milestoneManager.addMilestone(
        //    1 weeks,
        //    100e18,
        //    "My first Milestone",
        //    "Here could be a more detailed description"
        //);

        //milestoneManager.startNextMilestone();
    }
}
