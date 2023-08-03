// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualSupplyTokenTest} from "./VirtualSupplyTokenTest.sol";

/**
 * @dev Set virtual supply test
 */
contract SetVirtualSupply is VirtualSupplyTokenTest {
    function testSuccessSetVirtualSupply(uint amount) public {
        setVirtualSupply(amount);
        uint newVirtualSupply = totalVirtualSupply();
        assertEqUint(newVirtualSupply, amount);
    }
}
