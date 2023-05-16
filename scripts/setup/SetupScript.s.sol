// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import "../deployment/DeploymentScript.s.sol";

import {IMilestoneManager} from "../../src/modules/MilestoneManager.sol";
import {IProposal} from "../../src/proposal/Proposal.sol";
import {ERC20Mock} from "../../test/utils/mocks/ERC20Mock.sol";

contract SetupScript is Test, Script, DeploymentScript {
    using stdJson for string;
    /*
        // Before we can start a milestone, two things need to be present:
        // 1. A non-empty list of contributors for it
        // 2. The percentage of milestone funding to pay the contributors for the milestone.

        // So lets add Alice and Bob as contributors to the proposal.
        // Note the salary is specified in relation to the SALARY_PRECISION variable in the MilestoneManager.
    */

    IMilestoneManager.Contributor alice = IMilestoneManager.Contributor(
        address(0xA11CE), 50_000_000, "AliceIdHash"
    );

    IMilestoneManager.Contributor bob = IMilestoneManager.Contributor(
        address(0x606), 50_000_000, "BobIdHash"
    );

    IMilestoneManager.Contributor[] contributors;

    address funder1 = address(0xF1);
    address funder2 = address(0xF2);

    address proposalOwner = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    uint256 proposalOwnerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");

    function run() public override {
        ERC20Mock token;
        IProposal test_proposal;

        DeploymentScript.run();

        vm.startBroadcast(deployerPrivateKey);
        {
            token = new ERC20Mock("Mock", "MOCK");
        }
        vm.stopBroadcast();

        // First, we create a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory.ProposalConfig({
            owner: proposalOwner, 
            token: token
        });

        IProposalFactory.ModuleConfig[] memory optionalModules = new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = milestoneManagerFactoryConfig;

        vm.startPrank(proposalOwner);
        test_proposal = proposalFactory.createProposal(
                                            proposalConfig,
                                            authorizerFactoryConfig,
                                            paymentProcessorFactoryConfig,
                                            optionalModules
                                        );
        vm.stopPrank();

        string memory json = vm.readFile("broadcast/SetupScript.s.sol/31337/run-latest.json");
        // bytes memory transactionDetails = json.parseRaw("transactions[0].tx");
        // RawTx1559Detail memory rawTxDetail = abi.decode(transactionDetails, (RawTx1559Detail));
        // Tx1559Detail memory txDetail = rawToConvertedEIP1559Detail(rawTxDetail);
        // assertEq(txDetail.from, makeAddr("Beef"));

        uint index = 0;
        Receipt memory receipt = readReceipt("broadcast/SetupScript.s.sol/31337/run-latest.json", index);
        console2.log("Contract Address", receipt.contractAddress);
        //assertEq(receipt.contractAddress, address(0));

        // console2.log(latestRunJson);
        //console2.log("Transaction 2", transactions[2].contractName);
        // MilestoneManager proposalCreatedMilestoneManager = MilestoneManager(0x8198f5d8F8CfFE8f9C413d98a0A55aEB8ab9FbB7);

        // assertTrue(!(proposalCreatedMilestoneManager.isNextMilestoneActivatable()), "Milestone manager wrong address inputted");

        // contributors.push(alice);
        // contributors.push(bob);

        // vm.startPrank(address(test_proposal));
        // milestoneManager.addMilestone(
        //     1 weeks,
        //     1000e18,
        //     contributors,
        //     bytes("Here could be a more detailed description")
        // );
        // vm.stopPrank();

        // console2.log("ERC20 token address: ", address(token));
        // console2.log("Test Proposal address", address(test_proposal));
    }

}