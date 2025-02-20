// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import
    "test/modules/fundingManager/rebasing/abstracts/ElasticReceiptTokenBase_v1.t.sol";

/**
 * @dev Deployment Tests.
 */
contract Deployment is ElasticReceiptTokenBaseV1Test {
    function testInvariants() public {
        assertEq(ert.totalSupply(), 0);
        assertEq(ert.scaledBalanceOf(address(0)), TOTAL_BITS);
        assertEq(ert.scaledTotalSupply(), 0);
    }

    function testInitialization() public {
        assertEq(ert.underlier(), address(underlier));
        assertEq(ert.name(), NAME);
        assertEq(ert.symbol(), SYMBOL);
        assertEq(ert.decimals(), uint8(DECIMALS));
    }

    function testInitilizationFailsIfMintAlreadyExecuted(
        address user,
        uint amount
    ) public {
        vm.assume(user != address(0));
        vm.assume(user != address(ert));
        amount = bound(amount, 1, MAX_SUPPLY);

        underlier.mint(user, amount);

        vm.startPrank(user);
        {
            underlier.approve(address(ert), amount);
            ert.mint(amount);
        }
        vm.stopPrank();

        vm.expectRevert();
        ert.init(_erb_orchestrator, _ERB_METADATA, _erb_configData);
    }
}
