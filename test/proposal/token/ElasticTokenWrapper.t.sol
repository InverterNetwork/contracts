// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    ElasticTokenWrapper,
    IElasticTokenWrapper
} from "src/proposal/token/ElasticTokenWrapper.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ElasticTokenWrapperTest is Test {
    // SuT
    ElasticTokenWrapper tokenWrapper;

    ERC20Mock underlier;

    // Constants copied from ElasticTokenWrapper.
    uint constant MAX_TOKEN_SUPPLY = 10_000_000e18; // 10M

    // Constants copied from ElasticReceiptToken.
    uint constant MAX_SUPPLY = 1_000_000_000e18;

    function setUp() public {
        underlier = new ERC20Mock("Underlier Mock Token", "UNDERLIER");
        tokenWrapper =
        new ElasticTokenWrapper(underlier, "Elastic Token Wrapper", "WRAPPER");
    }

    function testDeployment() public {
        assertEq(address(tokenWrapper.underlying()), address(underlier));
        assertEq(tokenWrapper.name(), "Elastic Token Wrapper");
        assertEq(tokenWrapper.symbol(), "WRAPPER");

        // Constants
        assertEq(tokenWrapper.MAX_TOKEN_SUPPLY(), MAX_TOKEN_SUPPLY);
    }

    function testDepositAndWithdraw(
        address user,
        uint depositAmount,
        int rebasePercInBps
    ) public {
        vm.assume(user != address(0));
        vm.assume(user != address(tokenWrapper));
        vm.assume(user != address(underlier));

        vm.assume(depositAmount != 0);
        vm.assume(depositAmount < MAX_SUPPLY);

        vm.assume(rebasePercInBps > -10_000);
        vm.assume(rebasePercInBps < 10_000);

        // Mint tokens to user.
        underlier.mint(user, depositAmount);

        // User approves infinite tokens to tokenWrapper.
        vm.prank(user);
        underlier.approve(address(tokenWrapper), type(uint).max);

        // User deposits tokens and receives an amount of wrapped tokens.
        vm.prank(user);
        uint wrappedAmount = tokenWrapper.depositFor(user, depositAmount);

        // Simulate rebase by minting/burning tokens.
        uint rebasePercInBpsAbs =
            rebasePercInBps < 0 ? uint(-rebasePercInBps) : uint(rebasePercInBps);
        uint supplyDelta = (depositAmount * rebasePercInBpsAbs) / 10_000;
        if (rebasePercInBps < 0) {
            // Contraction
            underlier.burn(address(tokenWrapper), supplyDelta);
        } else {
            // Expansion
            underlier.mint(address(tokenWrapper), supplyDelta);
        }

        // User burn balance of wrapped tokens.
        vm.prank(user);
        uint withdrawedAmount = tokenWrapper.burnTo(user, wrappedAmount);

        // User receives the initial deposit plus/minus the rebase percentage
        // change back.
        if (rebasePercInBps < 0) {
            // Contraction
            assertApproxEqAbs(withdrawedAmount, depositAmount - supplyDelta, 1);
        } else {
            // Expansion
            assertApproxEqAbs(withdrawedAmount, depositAmount + supplyDelta, 1);
        }
    }
}
