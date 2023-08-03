// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {VirtualSupplyTokenUpgradeableMock} from
    "./utils/mocks/VirtualSupplyTokenUpgradeableMock.sol";

/**
 * @dev Root contract for VirtualSupplyToken Test Contracts.
 *
 *      Provides the setUp function, access to common test utils and internal
 *      constants from the ElasticReceiptToken.
 */
abstract contract VirtualSupplyTokenTest is Test {
    // Contract Instances
    VirtualSupplyTokenUpgradeableMock vstUpgradeableInstance;

    // Constants
    string internal constant NAME = "Bonding Curve Research Group";
    string internal constant SYMBOL = "BCRG";
    uint internal constant INITAL_VIRTUAL_SUPPLY = 1000e18;

    function setUp() public {
        vstUpgradeableInstance = new VirtualSupplyTokenUpgradeableMock();
        vstUpgradeableInstance.init(NAME, SYMBOL, INITAL_VIRTUAL_SUPPLY);
    }

    function setVirtualSupply(uint amount) public {
        vm.prank(msg.sender);
        vstUpgradeableInstance.setVirtualSupply(amount);
    }

    function totalVirtualSupply() public view returns (uint) {
        return vstUpgradeableInstance.totalVirtualSupply();
    }
}
