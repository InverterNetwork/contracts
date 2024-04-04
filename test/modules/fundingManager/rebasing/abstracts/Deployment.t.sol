// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ElasticReceiptTokenTest} from
    "test/modules/fundingManager/rebasing/abstracts/ElasticReceiptTokenTest.t.sol";

/**
 * @dev Deployment Tests.
 */
contract Deployment is ElasticReceiptTokenTest {
    function testInvariants() public {
        assertEq(ertb.totalSupply(), 0);
        assertEq(ertb.scaledBalanceOf(address(0)), TOTAL_BITS);
        assertEq(ertb.scaledTotalSupply(), 0);
    }

    function testContructor() public {
        // Constructor arguments.

        assertEq(ert.underlier(), address(underlier));
        assertEq(ert.name(), NAME);
        assertEq(ert.symbol(), SYMBOL);
        assertEq(ert.decimals(), uint8(DECIMALS));
    }

    //--------------------------------------------------------------------------
    // Upgradeable Specific Tests

    function testInitialization() public {
        assertEq(ertUpgradeable.underlier(), address(underlier));
        assertEq(ertUpgradeable.name(), NAME);
        assertEq(ertUpgradeable.symbol(), SYMBOL);
        assertEq(ertUpgradeable.decimals(), uint8(DECIMALS));
    }

    function testInitilizationFailsIfMintAlreadyExecuted(
        address user,
        uint amount
    ) public {
        vm.assume(user != address(0));
        vm.assume(user != address(ertUpgradeable));
        amount = bound(amount, 1, MAX_SUPPLY);

        underlier.mint(user, amount);

        vm.startPrank(user);
        {
            underlier.approve(address(ertUpgradeable), amount);
            ertUpgradeable.mint(amount);
        }
        vm.stopPrank();

        vm.expectRevert();
        ertUpgradeable.init(address(underlier), NAME, SYMBOL, uint8(DECIMALS));
    }
}
