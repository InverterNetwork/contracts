// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {InverterReverter_v1} from
    "src/external/reverter/InverterReverter_v1.sol";

contract InverterReverterV1Test is Test {
    // SuT
    InverterReverter_v1 reverter;

    function setUp() public {
        reverter = new InverterReverter_v1();
    }

    //--------------------------------------------------------------------------
    // Test: createDigest

    function testRevert(bytes memory data) public {
        vm.expectRevert(
            InverterReverter_v1.InverterReverter__ContractPaused.selector
        );

        (bool ok,) = address(reverter).call(data);
        ok;
    }
}
