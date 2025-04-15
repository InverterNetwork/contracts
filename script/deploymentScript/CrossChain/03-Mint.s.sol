// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {FM_BC_CC_Bancor_Redeeming_VS_v1} from
    "src/exp/FM_BC_CC_Bancor_Redeeming_VS_v1.sol";

contract MintScript is ProtocolConstants_v1 {
    address private fundingManager;

    function run() external {
        address fmaddress = vm.envAddress("FUNDING_MANAGER");
        console2.log("Funding Manager Address: ", fmaddress);

        fundingManager = address(0xaF7A2FDa02238C6988DE4c66dB2Db1F68927C0A5);
        ERC20Mock erc20Mock =
            ERC20Mock(0x4A679253410272dd5232B3Ff7cF5dbB88f295319);
        FM_BC_CC_Bancor_Redeeming_VS_v1 fm =
            FM_BC_CC_Bancor_Redeeming_VS_v1(fundingManager);

        vm.startBroadcast(deployerPrivateKey);

        erc20Mock.approve(fundingManager, 1 ether);

        uint virtualCollateralSupply = fm.getVirtualCollateralSupply();
        uint virtualIssuanceSupply = fm.getVirtualIssuanceSupply();

        console2.log(
            "Before Virtual Collateral Supply: ", virtualCollateralSupply
        );
        console2.log("Before Virtual Issuance Supply: ", virtualIssuanceSupply);

        fm.buyForCrossChain(deployer, 1 ether, 1, 31_338);

        virtualCollateralSupply = fm.getVirtualCollateralSupply();
        virtualIssuanceSupply = fm.getVirtualIssuanceSupply();

        console2.log(
            "After Virtual Collateral Supply: ", virtualCollateralSupply
        );
        console2.log("After Virtual Issuance Supply: ", virtualIssuanceSupply);

        vm.stopBroadcast();
    }
}
