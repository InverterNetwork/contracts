// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";



contract DeployMockToken is Script {

    function run() public {
        string memory name = vm.envString("NAME");
        string memory symbol = vm.envString("SYMBOL");
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        console2.log(
            "Deploying MockToken at address: ",
            address(
                new ERC20Mock(
                    name, symbol
                )
            )
        );

        vm.stopBroadcast();
    }
}
