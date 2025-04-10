// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {CrossChainTokenFactory_v1} from
    "../../../src/exp/CrossChainTokenFactory_v1.sol";

contract DeployReceiverScript is ProtocolConstants_v1 {
    function run() external {
        ERC20Issuance_v1 issuanceToken;

        issuanceToken =
            ERC20Issuance_v1(0x5FbDB2315678afecb367f032d93F642f64180aa3);

        uint balance = ERC20Issuance_v1(issuanceToken).balanceOf(deployer);

        console2.log("Balance: ", balance);
    }
}
