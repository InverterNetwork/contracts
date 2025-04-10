// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {LM_FM_IssuanceTokenBridge_v1} from
    "../../../src/exp/LM_FM_IssuenceTokenBridge_v1.sol";

import {FM_BC_CC_Bancor_Redeeming_VS_v1} from
    "src/exp/FM_BC_CC_Bancor_Redeeming_VS_v1.sol";
import {CrossChainDispatcher} from "src/exp/CrossChainDispatcher.sol";
import {HyperlaneAdapter} from "src/exp/HyperlaneAdapter.sol";

contract TokenBridgeSettingsScript is ProtocolConstants_v1 {
    address destinationMailbox = 0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8;
    address receiver = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address fundingManager = 0x75b33Fbe47f287D4C335e6dc0F6c9004dB487a13;

    function run() external {
        // LM_FM_IssuanceTokenBridge_v1 bridge = LM_FM_IssuanceTokenBridge_v1(
        //     0xBa92696CA776c595A5A7A583E22b1136cEB50850
        // );

        // vm.startBroadcast(deployerPrivateKey);

        // uint destinationChainId = 31_338;

        // bridge.addDestination(destinationChainId, destinationMailbox, receiver);

        // bridge.setIssuanceToken(0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8);

        // vm.stopBroadcast();

        deployDispatcher();
    }

    function deployDispatcher() internal {
        vm.startBroadcast(deployerPrivateKey);
        {
            CrossChainDispatcher dispatcher = new CrossChainDispatcher();
            HyperlaneAdapter adapter =
                new HyperlaneAdapter(destinationMailbox, receiver);
            dispatcher.registerAdapter(31_338, address(adapter));

            FM_BC_CC_Bancor_Redeeming_VS_v1(fundingManager).setDispatcher(
                address(dispatcher)
            );

            console2.log("Dispatcher Address: ", address(dispatcher));
            console2.log("Adapter Address: ", address(adapter));
        }
        vm.stopBroadcast();
    }
}
