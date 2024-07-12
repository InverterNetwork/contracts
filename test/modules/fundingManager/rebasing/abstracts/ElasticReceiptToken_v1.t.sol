// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ElasticReceiptTokenBaseV1Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ElasticReceiptTokenBaseV1Mock.sol";

import {ElasticReceiptTokenV1Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ElasticReceiptTokenV1Mock.sol";

import {ElasticReceiptTokenUpgradeableV1Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ElasticReceiptTokenUpgradeableV1Mock.sol";

import {ERC20Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ERC20Mock.sol";

/**
 * @dev Root contract for ElasticReceiptToken_v1 Test Contracts.
 *
 *      Provides the setUp function, access to common test utils and internal
 *      constants from the ElasticReceiptToken_v1.
 */
abstract contract ElasticReceiptTokenV1Test is Test {
    // SuT
    ElasticReceiptTokenBaseV1Mock ertb;
    ElasticReceiptTokenV1Mock ert;
    ElasticReceiptTokenUpgradeableV1Mock ertUpgradeable;

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

        ertb = new ElasticReceiptTokenBaseV1Mock(
            address(underlier), NAME, SYMBOL, uint8(DECIMALS)
        );

        ert = new ElasticReceiptTokenV1Mock(
            address(underlier), NAME, SYMBOL, uint8(DECIMALS)
        );

        ertUpgradeable = new ElasticReceiptTokenUpgradeableV1Mock();
        ertUpgradeable.init(address(underlier), NAME, SYMBOL, uint8(DECIMALS));
    }

    modifier assumeTestAmount(uint amount) {
        vm.assume(amount != 0 && amount <= MAX_SUPPLY);
        _;
    }

    modifier assumeTestAddress(address who) {
        vm.assume(who != address(0));
        vm.assume(who != address(ertb));
        _;
    }

    function mintToUser(address user, uint erts) public {
        underlier.mint(user, erts);

        vm.startPrank(user);
        {
            underlier.approve(address(ertb), type(uint).max);
            ertb.mint(erts);
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
