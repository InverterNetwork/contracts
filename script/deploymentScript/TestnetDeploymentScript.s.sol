// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {DeploymentScript} from "script/deploymentScript/DeploymentScript.s.sol";

contract TestnetDeploymentScript is DeploymentScript {
    function run() public override {
        super.run();

        // BancorFormula, ERC20Mock and UMAoracleMock
    }
}
