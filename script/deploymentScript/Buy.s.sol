// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {LM_FM_IssuanceTokenBridge_v1} from
    "../../src/exp/LM_FM_IssuenceTokenBridge_v1.sol";

contract BuyScript is ProtocolConstants_v1 {
    address private fundingManager;

    function run() external {
        fundingManager = address(0x301B26831bc208b572C20D36d82C47B561CaB1BF);
        IBondingCurveBase_v1 bondingCurve = IBondingCurveBase_v1(fundingManager);
        ERC20Mock erc20Mock =
            ERC20Mock(0x4A679253410272dd5232B3Ff7cF5dbB88f295319);
        LM_FM_IssuanceTokenBridge_v1 bridge = LM_FM_IssuanceTokenBridge_v1(
            0xBa92696CA776c595A5A7A583E22b1136cEB50850
        );

        ERC20Issuance_v1 issuanceToken =
            ERC20Issuance_v1(0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8);

        vm.startBroadcast(deployerPrivateKey);

        erc20Mock.approve(fundingManager, 1 ether);
        bondingCurve.buy(1 ether, 1);

        uint initialBalance = issuanceToken.balanceOf(deployer);

        issuanceToken.approve(address(bridge), initialBalance);

        uint32 destinationChainId = 31_338;
        bridge.bridge(destinationChainId, initialBalance);

        console2.log("Bridged Amount: ", initialBalance);
        console2.log("Final Balance: ", issuanceToken.balanceOf(deployer));

        vm.stopBroadcast();
    }
}
