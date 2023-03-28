// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Proposal} from "../../src/proposal/Proposal.sol";

contract DeployProposalContract is Script {
    Proposal proposal;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        {
            proposal = new Proposal();
        }
        vm.stopBroadcast();

        console2.log("Proposal Contract Deployed at: ", address(proposal));
    }
}