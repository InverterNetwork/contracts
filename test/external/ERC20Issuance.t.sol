// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {
    ERC20Issuance_v1,
    IERC20Issuance_v1,
    ERC20Capped
} from "@ex/token/ERC20Issuance_v1.sol";

import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

contract ERC20IssuanceTest is Test {
    ERC20Issuance_v1 token;

    event MinterSet(address indexed minter, bool allowed);

    function setUp() public {
        token = new ERC20Issuance_v1(
            "Test Token",
            "TT",
            18,
            type(uint).max - 1,
            address(this),
            address(this)
        );
    }

    function testInit() public {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TT");
        assertEq(token.decimals(), 18);
        assertEq(token.cap(), type(uint).max - 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.owner(), address(this));
        assertEq(token.allowedMinters(address(this)), true);
    }

    /*
    test setMinter
    ├── When the caller is not the Admin
    │   └── It should revert
    └── When the caller is the Admin
        └── It should set the new minter address rights
    */

    function testSetMinterFails_IfCallerNotAdmin() public {
        vm.startPrank(address(0xB0B));
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                    address(0xB0B)
                )
            );

            token.setMinter(address(this), true);
        }
    }

    function test_setMinter(address minter) public {
        vm.expectEmit(true, true, true, true);
        emit MinterSet(minter, true);

        token.setMinter(minter, true);

        assertTrue(token.allowedMinters(minter));

        vm.expectEmit(true, true, true, true);
        emit MinterSet(minter, false);

        token.setMinter(minter, false);

        assertFalse(token.allowedMinters(minter));
    }

    function test_setMinter_Idempotence(address minter, bool allowed) public {
        // Sometimes we the initial state is that the address is allowed
        if (uint(uint160(minter)) % 2 == 0) {
            token.setMinter(minter, true);
        }

        vm.expectEmit(true, true, true, true);
        emit MinterSet(minter, allowed);

        token.setMinter(minter, allowed);

        // state after
        assertEq(token.allowedMinters(minter), allowed);
    }

    /*
    test mint
    ├── When the caller is not the Minter
    │   └── It should revert
    ├── When the mint amount would exceed the maximum supply
    │   └── It should revert
    └── When the mint amount is valid and the caller is allowed
    └── It should mint the tokens
    */
    function testMintFails_IfCallerNotMinter() public {
        vm.startPrank(address(0xB0B));
        {
            vm.expectRevert(
                IERC20Issuance_v1.IERC20Issuance__CallerIsNotMinter.selector
            );
            token.mint(address(this), 100);
        }
    }

    function testMintFails_IfMintExceedsMaximumSupply() public {
        uint excessiveSupply = token.cap() + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Capped.ERC20ExceededCap.selector,
                excessiveSupply,
                token.cap()
            )
        );
        token.mint(address(this), excessiveSupply);
    }

    function test_Mint(uint amount) public {
        vm.assume(amount < token.cap());

        uint supplyBefore = token.totalSupply();

        token.mint(address(this), amount);

        assertEq(token.totalSupply(), supplyBefore + amount);
    }

    /*
    test burn
    ├── When the caller is not the Minter
    │   └── It should revert
    └── When the caller is not the Minter
    └── It should burn 
    */

    function testBurnFails_IfCallerNotMinter() public {
        vm.startPrank(address(0xB0B));
        {
            vm.expectRevert(
                IERC20Issuance_v1.IERC20Issuance__CallerIsNotMinter.selector
            );
            token.burn(address(this), 100);
        }
    }

    function test_Burn(uint amount) public {
        vm.assume(amount < token.cap());

        uint supplyBefore = token.totalSupply();

        token.mint(address(this), amount);
        token.burn(address(this), amount);

        assertEq(token.totalSupply(), supplyBefore);
    }
}
