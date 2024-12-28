// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {LM_FM_IssuanceTokenBridge_v1} from
    "../../src/exp/LM_FM_IssuenceTokenBridge_v1.sol";

contract TokenBridgeSettingsScript is ProtocolConstants_v1 {
    function run() external {
        LM_FM_IssuanceTokenBridge_v1 bridge = LM_FM_IssuanceTokenBridge_v1(
            0xBa92696CA776c595A5A7A583E22b1136cEB50850
        );

        vm.startBroadcast(deployerPrivateKey);

        uint destinationChainId = 31_338;
        address destinationMailbox = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318;
        address receiver = 0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44;

        bridge.addDestination(destinationChainId, destinationMailbox, receiver);

        bridge.setIssuanceToken(0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8);

        vm.stopBroadcast();
    }
}
