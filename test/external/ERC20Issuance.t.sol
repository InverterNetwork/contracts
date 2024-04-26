// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {
    ERC20Issuance_v1,
    IERC20Issuance_v1
} from "@fm/bondingCurve/tokens/ERC20Issuance_v1.sol";

import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

contract ERC20IssuanceTest is Test {
    ERC20Issuance_v1 token;

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

    /*
    test setMinter
    ├── When the caller is not the Owner
    │   └── It should revert
    └── When the caller is the Owner
    └── It should set the new minter address
    */

    function testSetMinterFails_IfCallerNotOwner() public {
        vm.startPrank(address(0xB0B));
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                    address(0xB0B)
                )
            );

            token.setMinter(address(this));
        }
    }

    function test_setMinter() public {
        token.setMinter(address(0xB0B));

        assertEq(token.allowedMinter(), address(0xB0B));
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
        uint excessiveSupply = token.MAX_SUPPLY() + 1;

        vm.expectRevert(
            IERC20Issuance_v1.IERC20Issuance__MintExceedsSupplyCap.selector
        );
        token.mint(address(this), excessiveSupply);
    }

    function test_Mint(uint amount) public {
        vm.assume(amount < token.MAX_SUPPLY());

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
        vm.assume(amount < token.MAX_SUPPLY());

        uint supplyBefore = token.totalSupply();

        token.mint(address(this), amount);
        token.burn(address(this), amount);

        assertEq(token.totalSupply(), supplyBefore);
    }
}
