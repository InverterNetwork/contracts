// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {CrossChainTokenFactory_v1} from
    "../../src/exp/CrossChainTokenFactory_v1.sol";

contract DeployReceiverScript is ProtocolConstants_v1 {
    function run() external {
        ERC20Issuance_v1 issuanceToken;
        CrossChainTokenFactory_v1 factory;

        // vm.startBroadcast(deployerPrivateKey);

        // issuanceToken = new ERC20Issuance_v1(
        //     "Inverter Token", "INVT", 18, 100_000_000 ether, deployer
        // );

        // factory = new CrossChainTokenFactory_v1(address(issuanceToken));

        // issuanceToken.setMinter(address(factory), true);

        // vm.stopBroadcast();

        // console2.log("Deployer: ", deployer);
        // console2.log("Issuance Token: ", address(issuanceToken));
        // console2.log("Factory: ", address(factory));

        uint balance = ERC20Issuance_v1(
            0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1
        ).balanceOf(deployer);

        console2.log("Balance: ", balance);
    }
}
