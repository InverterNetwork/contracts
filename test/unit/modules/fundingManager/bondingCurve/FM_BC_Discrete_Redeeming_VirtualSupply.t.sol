// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FM_BC_Discrete_Redeeming_VirtualSupply} from "../../../../../src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply.sol";

contract FM_BC_Discrete_Redeeming_VirtualSupply_Test is Test {
    FM_BC_Discrete_Redeeming_VirtualSupply public fmBcDiscrete;

    function setUp() public {
        fmBcDiscrete = new FM_BC_Discrete_Redeeming_VirtualSupply();
    }

    function test_Dummy() public {
        assertTrue(true);
    }
}
