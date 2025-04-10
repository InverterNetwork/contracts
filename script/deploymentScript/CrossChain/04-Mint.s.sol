// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {FM_BC_CC_Bancor_Redeeming_VS_v1} from
    "src/exp/FM_BC_CC_Bancor_Redeeming_VS_v1.sol";

import {HyperlaneAdapter} from "src/exp/HyperlaneAdapter.sol";

contract MintScript is ProtocolConstants_v1 {
    address private fundingManager;

    function run() external {
        fundingManager = address(0x75b33Fbe47f287D4C335e6dc0F6c9004dB487a13);
        ERC20Mock erc20Mock =
            ERC20Mock(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);
        FM_BC_CC_Bancor_Redeeming_VS_v1 fm =
            FM_BC_CC_Bancor_Redeeming_VS_v1(fundingManager);

        ERC20Issuance_v1 issuanceToken =
            ERC20Issuance_v1(0x1fA02b2d6A771842690194Cf62D91bdd92BfE28d);

        vm.startBroadcast(deployerPrivateKey);

        erc20Mock.approve(fundingManager, 1 ether);
        fm.buyForCrossChain(deployer, 1 ether, 1, 31_338);

        // HyperlaneAdapter adapter =
        //     HyperlaneAdapter(0x4631BCAbD6dF18D94796344963cB60d44a4136b6);
        // adapter.sendMintMessage(deployer, 1 ether, 31_338);

        uint initialBalance = issuanceToken.balanceOf(deployer);

        console2.log("Bridged Amount: ", initialBalance);
        console2.log("Final Balance: ", issuanceToken.balanceOf(deployer));

        vm.stopBroadcast();
    }
}
