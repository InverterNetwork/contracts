// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {MintWrapper} from "@ex/token/MintWrapper.sol";

import {
    ERC20Issuance_v1,
    IERC20Issuance_v1,
    ERC20Capped
} from "@ex/token/ERC20Issuance_v1.sol";
import {Ownable} from "@oz/access/Ownable.sol";

contract MintWrapperTest is Test {
    ERC20Issuance_v1 token;
    MintWrapper wrapper;

    function setUp() public {
        token = new ERC20Issuance_v1(
            "Test Token", "TT", 18, type(uint).max - 1, address(this)
        );
        wrapper = new MintWrapper(token, address(this));
        token.setMinter(address(wrapper), true);
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
                    Ownable.OwnableUnauthorizedAccount.selector, address(0xB0B)
                )
            );

            wrapper.setMinter(address(this), true);
        }
        vm.stopPrank();
    }

    function test_setMinter(address minter) public {
        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_v1.MinterSet(minter, true);

        wrapper.setMinter(minter, true);

        assertTrue(wrapper.allowedMinters(minter));

        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_v1.MinterSet(minter, false);

        wrapper.setMinter(minter, false);

        assertFalse(wrapper.allowedMinters(minter));
    }

    function test_setMinter_Idempotence(address minter, bool allowed) public {
        // Sometimes we the initial state is that the address is allowed
        if (uint(uint160(minter)) % 2 == 0) {
            wrapper.setMinter(minter, true);
        }

        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_v1.MinterSet(minter, allowed);

        wrapper.setMinter(minter, allowed);

        // state after
        assertEq(wrapper.allowedMinters(minter), allowed);
    }

    /*
    test mint
    ├── When the caller is not the Minter
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
            wrapper.mint(address(this), 100);
        }
    }

    function test_Mint(uint amount) public {
        wrapper.setMinter(address(this), true);

        vm.assume(amount < token.cap());

        uint supplyBefore = token.totalSupply();

        wrapper.mint(address(this), amount);

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
        wrapper.setMinter(address(this), true);

        vm.assume(amount < token.cap());

        uint supplyBefore = token.totalSupply();

        token.mint(address(this), amount);
        token.burn(address(this), amount);

        assertEq(token.totalSupply(), supplyBefore);
    }
}
