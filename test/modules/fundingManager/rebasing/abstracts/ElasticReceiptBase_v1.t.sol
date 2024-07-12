// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {ElasticReceiptBaseV1Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ElasticReceiptBaseV1Mock.sol";

import {ERC20Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ERC20Mock.sol";

/**
 * @dev Root contract for ElasticReceiptBase_v1 Test Contracts.
 *
 *      Provides the setUp function, access to common test utils and internal
 *      constants from the ElasticReceiptBase_v1.
 */
abstract contract ElasticReceiptBaseV1Test is Test {
    // SuT
    ElasticReceiptBaseV1Mock ert;

    // Mocks
    ERC20Mock underlier;

    // Constants
    string internal constant NAME = "elastic receipt Token";
    string internal constant SYMBOL = "ERT";
    uint internal constant DECIMALS = 9;

    // Constants copied from SuT.
    uint internal constant MAX_UINT = type(uint).max;
    uint internal constant MAX_SUPPLY = 1_000_000_000_000_000_000e18;
    uint internal constant TOTAL_BITS = MAX_UINT - (MAX_UINT % MAX_SUPPLY);
    uint internal constant BITS_PER_UNDERLYING = TOTAL_BITS / MAX_SUPPLY;

    function setUp() public {
        underlier = new ERC20Mock("Test ERC20", "TEST");

        address impl = address(new ElasticReceiptBaseV1Mock());
        ert = ElasticReceiptBaseV1Mock(Clones.clone(impl));

        ert.init(NAME, SYMBOL, uint8(DECIMALS));
        ert.setUnderlier(address(underlier));
    }

    modifier assumeTestAmount(uint amount) {
        vm.assume(amount != 0 && amount <= MAX_SUPPLY);
        _;
    }

    modifier assumeTestAddress(address who) {
        vm.assume(who != address(0));
        vm.assume(who != address(ert));
        _;
    }

    function mintToUser(address user, uint erts) public {
        underlier.mint(user, erts);

        vm.startPrank(user);
        {
            underlier.approve(address(ert), type(uint).max);
            ert.mint(erts);
        }
        vm.stopPrank();
    }

    function underflows(uint a, uint b) public pure returns (bool) {
        unchecked {
            uint x = a - b;
            return x > a;
        }
    }
}
