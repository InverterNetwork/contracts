// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import
    "test/modules/fundingManager/rebasing/abstracts/ElasticReceiptToken_v1.t.sol";

/**
 * @dev Mint/Burn Tests.
 */
contract MintBurn is ElasticReceiptTokenV1Test {
    function testFailMintMoreThanMaxSupply(address to) public {
        vm.assume(to != address(0));

        // Fails with MaxSupplyReached.
        mintToUser(to, MAX_SUPPLY + 1);
    }

    function testFailBurnAll(address to, uint erts) public {
        vm.assume(to != address(0));
        vm.assume(erts != 0);

        mintToUser(to, erts);

        // Fails with Division by 0.
        vm.prank(to);
        ert.burn(erts);
    }
}
