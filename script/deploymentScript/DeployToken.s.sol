// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {ERC20Issuance_Factory_v1} from "src/factories/custom/TokenFactory.sol";

import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {MintWrapper} from "src/external/token/MintWrapper.sol";

contract DeployTokenScript is Script {
    // Factory address to use for deployment
    address public tokenFactory = 0x5F3D29e225DEf9959a638423F01361aF4300Fdb2;

    function run() public {
        require(tokenFactory != address(0), "Token factory address not set");

        // Get deployment parameters from environment
        string memory name = "Alpha Chad";
        string memory symbol = "ACHAD"; 
        uint8 decimals = 18;
        uint256 maxSupply = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
        address owner = 0xB4f8D886E9e831B6728D16Ed7F3a6c27974ABAA4;
        uint256 nonce = vm.getNonce(tokenFactory);
        console2.log("Current factory nonce: %d", nonce);

        console2.log("Deploying token with parameters:");
        console2.log("Name: %s", name);
        console2.log("Symbol: %s", symbol);
        console2.log("Decimals: %d", decimals);
        console2.log("Max Supply: %d", maxSupply);
        console2.log("Owner: %s", owner);




        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        (ERC20Issuance_v1 token, MintWrapper mintWrapper) = ERC20Issuance_Factory_v1(tokenFactory).deployToken(
            name,
            symbol,
            decimals,
            maxSupply,
            owner
        );

        vm.stopBroadcast();

        console2.log("Token deployed at: %s", address(token));
        console2.log("Mint Wrapper deployed at: %s", address(mintWrapper));

        uint256 newNonce = vm.getNonce(tokenFactory);
        console2.log("New factory nonce: %d", newNonce);
    }
}
