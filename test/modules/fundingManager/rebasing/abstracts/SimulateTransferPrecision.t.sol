// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import
    "test/modules/fundingManager/rebasing/abstracts/ElasticReceiptToken_v1.t.sol";

/**
 * @dev Simulation to Test rhAmple's Transfer Precision.
 *
 *      Tests the following invariant:
 *
 *      If address A transfers x erts to address B, A's resulting external
 *      balance decreased by precisely x erts and B's external balance
 *      increased by precisely x erts.
 *
 *      To run the simulation, adjust the following two constants:
 *
 *          - MAX_ITERATIONS
 *              The number of iterations the simulation should have.
 *              Defines the supply change per iteration as:
 *                  supplyChange = MAX_SUPPLY / MAX_ITERATIONS
 *
 *          - SIMULATE_EXPANSION
 *              Defines if the supply should expand from 1 to MAX_SUPPLY
 *              or contract from MAX_SUPPLY to 1.
 *
 */
contract SimulateTransferPrecision is ElasticReceiptTokenV1Test {
    // The granularity by which the supply should be adjusted in each iteration.
    // Should not be zero due to div by zero at compile time.
    uint constant MAX_ITERATIONS = 1;

    // Wether expansion or contraction should be simulated.
    bool constant SIMULATE_EXPANSION = true;

    function testSimulation() public {
        if (MAX_ITERATIONS == 1) {
            emit log_string("No simulation ran.");
            emit log_string(
                "For more information see SimulateTransferPrecision.t.sol"
            );
            return;
        }

        if (SIMULATE_EXPANSION) {
            emit log_string("Simulate Expansion");
        } else {
            emit log_string("Simulate Contraction");
        }

        uint currentSupply = SIMULATE_EXPANSION
            ? 1 // Min supply to simulate expansion.
            : MAX_SUPPLY; // Max supply to simulate contraction.
        uint nextSupplyChange = MAX_SUPPLY / MAX_ITERATIONS;

        address u1 = address(1);
        address u2 = address(2);

        // Users give infinite approval of mock tokens to downstream contract.
        vm.prank(u1);
        underlier.approve(address(ert), type(uint).max);
        vm.prank(u2);
        underlier.approve(address(ert), type(uint).max);

        // Users give infinite approval of erts to this contract.
        vm.prank(u1);
        ert.approve(address(this), type(uint).max);
        vm.prank(u2);
        ert.approve(address(this), type(uint).max);

        // User 1 receives currentSupply of erts.
        mintToUser(u1, currentSupply);

        uint iteration;
        while (true) {
            iteration++;
            emit log_named_uint("Iteration", iteration);

            // Calculate current supply.
            currentSupply = SIMULATE_EXPANSION
                ? currentSupply + nextSupplyChange
                : currentSupply - nextSupplyChange;
            emit log_named_uint("Supply", currentSupply);

            // Stop simulation if MAX_SUPPLY reached or underflows occurs.
            if (SIMULATE_EXPANSION) {
                if (currentSupply > MAX_SUPPLY) {
                    emit log_string("End Simulation: MAX_SUPPLY reached");
                    break;
                }
            } else {
                if (underflows(currentSupply, nextSupplyChange)) {
                    emit log_string("End Simulation: Min supply reached");
                    break;
                }
            }

            // Mint/Burn nextSupplyChange of underlier tokens to downstream
            // contract to simulate expansion/contraction and execute rebase.
            if (SIMULATE_EXPANSION) {
                underlier.mint(address(ert), nextSupplyChange);
            } else {
                underlier.burn(address(ert), nextSupplyChange);
            }
            ert.rebase();

            // Cache balance, send 1e-9 ert back and forth,
            // and check if balance is same afterwards.
            uint balanceU1 = ert.balanceOf(u1);
            uint balanceU2 = ert.balanceOf(u2);
            ert.transferFrom(u1, u2, 1);
            ert.transferFrom(u2, u1, 1);
            assertEq(balanceU1, ert.balanceOf(u1));
            assertEq(balanceU2, ert.balanceOf(u2));

            // Cache balance, send whole ert balance back and forth,
            // and check if balance is same afterwards.
            balanceU1 = ert.balanceOf(u1);
            balanceU2 = ert.balanceOf(u2);
            ert.transferFrom(u1, u2, ert.balanceOf(u1));
            ert.transferFrom(u2, u1, ert.balanceOf(u2));
            assertEq(balanceU1, ert.balanceOf(u1));
            assertEq(balanceU2, ert.balanceOf(u2));
        }
    }
}
