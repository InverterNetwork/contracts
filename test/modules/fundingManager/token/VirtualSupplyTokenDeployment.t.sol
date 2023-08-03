// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {VirtualSupplyTokenTest} from "./VirtualSupplyTokenTest.sol";

/**
 * @dev Deployment Tests.
 */
contract VirtualSupplyTokenDeployment is VirtualSupplyTokenTest {
    //--------------------------------------------------------------------------
    // Upgradeable Specific Tests

    function testInitialization() public {
        assertEq(vstUpgradeableInstance.name(), NAME);
        assertEq(vstUpgradeableInstance.symbol(), SYMBOL);
        assertEq(
            vstUpgradeableInstance.totalVirtualSupply(), INITAL_VIRTUAL_SUPPLY
        );
    }
}
