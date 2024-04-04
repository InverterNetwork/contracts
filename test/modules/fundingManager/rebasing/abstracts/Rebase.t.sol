// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ElasticReceiptTokenTest} from
    "test/modules/fundingManager/rebasing/abstracts/ElasticReceiptTokenTest.t.sol";

/**
 * @dev Rebase Tests.
 *
 *      Uses a table-driven test approach.
 */
contract Rebase is ElasticReceiptTokenTest {
    /// @notice Event emitted when the balance scalar is updated.
    /// @param epoch The number of rebases since inception.
    /// @param newScalar The new scalar.
    event Rebase(uint indexed epoch, uint newScalar);

    struct TestCase {
        // The user balances.
        uint[2] balances;
        // The new supply target for the rebase operation.
        uint newSupplyTarget;
    }

    // Tests that if two rebase operations were executed, with the second one
    // bringing the supply back to the initial supply, the user balances did
    // not change.
    // Also checks if user balances rebased into the "right direction", i.e.
    // expanded on expansion, contracted on contraction or did not change due
    // to equilibrium rebase.
    function testRebaseTables() public {
        TestCase[5] memory testTable = [
            // Equilibrium rebase.
            TestCase([uint(1e18), 1e18], 2e18),
            // Rebase from min to max.
            TestCase([uint(1), 1], MAX_SUPPLY),
            // Max supply in one user with min rebase.
            TestCase([uint(MAX_SUPPLY - 1), 1], 1),
            // Max supply in one user with max rebase.
            TestCase([uint(MAX_SUPPLY - 1), 1], MAX_SUPPLY),
            // Max supply splitted with min rebase.
            TestCase([uint(MAX_SUPPLY / 2), MAX_SUPPLY / 2], 1)
        ];

        // Execute each test case.
        for (uint i; i < testTable.length; i++) {
            TestCase memory testCase = testTable[i];
            uint[2] memory balances = testCase.balances;

            // Start with a fresh setup after each iteration.
            setUp();

            // Init user balances and calculate total expected supply.
            uint totalSupply;
            for (uint j; j < balances.length; j++) {
                setUpUserBalance(toAddress(j), balances[j]);

                totalSupply += balances[j];
            }

            // Check total supply.
            assertEq(ertb.totalSupply(), totalSupply);

            // Check that a user balance did not change due to a mint by
            // another user.
            for (uint j; j < balances.length; j++) {
                assertEq(ertb.balanceOf(toAddress(j)), balances[j]);
            }

            // Change the underlier's supply and execute rebase.
            underlier.burn(address(ertb), underlier.balanceOf(address(ertb)));
            underlier.mint(address(ertb), testCase.newSupplyTarget);

            vm.expectEmit(false, false, false, false);
            emit Rebase(0, 0); //we don't know the new values, so we just emit a dummy value

            ertb.rebase();

            // Check that the user balances rebased into the "right direction",
            // i.e. expanded on expansion, contracted on contraction and did not
            // change during equilibrium rebase.
            for (uint j; j < balances.length; j++) {
                if (testCase.newSupplyTarget > totalSupply) {
                    assertTrue(ertb.balanceOf(toAddress(j)) > balances[j]);
                } else if (testCase.newSupplyTarget < totalSupply) {
                    assertTrue(ertb.balanceOf(toAddress(j)) < balances[j]);
                } else {
                    assertEq(ertb.balanceOf(toAddress(j)), balances[j]);
                }
            }

            // Execute second rebase to bring the supply back to initial.
            underlier.burn(address(ertb), underlier.balanceOf(address(ertb)));
            underlier.mint(address(ertb), totalSupply);

            vm.expectEmit(false, false, false, false);
            emit Rebase(0, 0); //we don't know the new values, so we just emit a dummy value

            ertb.rebase();

            // Check that user balances did not change compared to initial.
            for (uint j; j < balances.length; j++) {
                assertEq(ertb.balanceOf(toAddress(j)), balances[j]);
            }
        }
    }

    function testNoRebaseIfZeroSupplyTarget() public {
        underlier.mint(address(ertb), 10e18);
        ertb.rebase();

        uint supplyBefore = ertb.totalSupply();
        assertEq(supplyBefore, 10e18);

        underlier.burn(address(ertb), 10e18);
        ertb.rebase();

        uint supplyAfter = ertb.totalSupply();

        // Did not adjust the supply.
        assertEq(supplyAfter, supplyBefore);
    }

    function testNoRebaseIfMaxSupplyTarget() public {
        underlier.mint(address(ertb), 10e18);
        ertb.rebase();

        uint supplyBefore = ertb.totalSupply();
        assertEq(supplyBefore, 10e18);

        underlier.mint(address(ertb), MAX_SUPPLY - 10e18 + 1);
        ertb.rebase();

        uint supplyAfter = ertb.totalSupply();

        // Did not adjust the supply.
        assertEq(supplyAfter, supplyBefore);
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function setUpUserBalance(address user, uint balance) public {
        underlier.mint(user, balance);

        vm.startPrank(user);
        {
            underlier.approve(address(ertb), balance);
            ertb.mint(balance);
        }
        vm.stopPrank();

        ertb.rebase();
    }

    function toAddress(uint a) public pure returns (address) {
        return address(uint160(a + 1));
    }
}
