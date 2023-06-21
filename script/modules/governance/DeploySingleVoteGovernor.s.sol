// pragma solidity ^0.8.0;

// import "forge-std/Script.sol";

// import {SingleVoteGovernor} from "src/modules/authorizer/SingleVoteGovernor.sol";

// /**
//  * @title SingleVoteGovernor Deployment Script
//  *
//  * @dev Script to deploy a new SingleVoteGovernor.
//  *
//  *
//  * @author Inverter Network
//  */

// contract DeploySingleVoteGovernor is Script {
//     // ------------------------------------------------------------------------
//     // Fetch Environment Variables
//     uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
//     address deployer = vm.addr(deployerPrivateKey);

//     SingleVoteGovernor singleVoteGovernor;

//     function run() external returns (address) {
//         vm.startBroadcast(deployerPrivateKey);
//         {
//             // Deploy the singleVoteGovernor.

//             singleVoteGovernor = new SingleVoteGovernor();
//         }

//         vm.stopBroadcast();

//         // Log the deployed SingleVoteGovernor contract address.
//         console2.log(
//             "Deployment of SingleVoteGovernor Implementation at address",
//             address(singleVoteGovernor)
//         );

//         return address(singleVoteGovernor);
//     }
// }
