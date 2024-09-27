// SPDX-License-Identifier: Ecosystem
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {NativeIssuance_v1} from "@ex/token/NativeIssuance_v1.sol";
import {INativeIssuance_v1} from "@ex/token/INativeIssuance_v1.sol";
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {NativeMinterMock} from "test/utils/mocks/external/NativeMinterMock.sol";

contract NativeIssuanceTest is Test {
    NativeIssuance_v1 public nativeIssuance;
    address public initialOwner = address(0x1);
    address public minter = address(0x2);
    address public user = address(0x3);
    uint public mintAmount = 100 ether;
    uint public burnAmount = 50 ether;

    function setUp() public {
        NativeMinterMock nativeMinter = new NativeMinterMock();
        vm.etch(
            0x0200000000000000000000000000000000000001,
            address(nativeMinter).code
        );
        vm.deal(0x0200000000000000000000000000000000000001, 1000 ether);

        nativeIssuance = new NativeIssuance_v1(initialOwner);
        // Set the minter to the contract itself for testing purposes
        vm.startPrank(initialOwner);
        nativeIssuance.setMinter(address(this), true);
        vm.stopPrank();
    }

    function testInitialState() public {
        assertEq(nativeIssuance.totalMinted(), 0);
        assertEq(nativeIssuance.balanceOf(initialOwner), 0);
        assertTrue(!nativeIssuance.allowedMinters(minter));
        assertEq(nativeIssuance.owner(), initialOwner);
    }

    function testMint() public {
        vm.startPrank(initialOwner);

        vm.expectEmit(true, true, false, true);
        emit INativeIssuance_v1.Minted(initialOwner, mintAmount);

        nativeIssuance.mint(initialOwner, mintAmount);

        vm.expectEmit(true, true, false, true);
        emit INativeIssuance_v1.Minted(user, mintAmount);

        nativeIssuance.mint(user, mintAmount);

        assertEq(nativeIssuance.totalMinted(), mintAmount + mintAmount);
        assertEq(nativeIssuance.balanceOf(initialOwner), mintAmount);
        assertEq(nativeIssuance.balanceOf(user), mintAmount);
    }

    function testMintRevertWhenNotMinter() public {
        vm.startPrank(user);
        vm.expectRevert(
            IERC20Issuance_v1.IERC20Issuance__CallerIsNotMinter.selector
        );
        nativeIssuance.mint(initialOwner, mintAmount);
    }

    function testMintRevertWhenMintToZeroAddress() public {
        vm.startPrank(initialOwner);
        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__InvalidAddress.selector
        );
        nativeIssuance.mint(address(0), mintAmount);
    }

    function testBurn() public {
        // First, mint some tokens to the initialOwner
        vm.startPrank(initialOwner);
        nativeIssuance.mint(initialOwner, mintAmount);
        assertEq(nativeIssuance.balanceOf(initialOwner), mintAmount);

        // Deposit amount to be burned into the contract
        nativeIssuance.depositNative{value: burnAmount}(initialOwner);

        // Now, burn a portion of those tokens
        nativeIssuance.burn(initialOwner, burnAmount);
        assertEq(
            nativeIssuance.totalNativeAssetSupply(), mintAmount - burnAmount
        );
        assertEq(
            nativeIssuance.balanceOf(initialOwner), mintAmount - burnAmount
        );
    }

    function testBurnRevertWhenNotMinter() public {
        vm.startPrank(user);
        vm.expectRevert(
            IERC20Issuance_v1.IERC20Issuance__CallerIsNotMinter.selector
        );
        nativeIssuance.burn(initialOwner, burnAmount);
    }

    function testBurnRevertWhenAddressZero() public {
        vm.startPrank(initialOwner);
        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__InvalidAddress.selector
        );
        nativeIssuance.burn(address(0), burnAmount);
    }

    function testBurnRevertWhenInvalidAmount() public {
        vm.startPrank(initialOwner);
        nativeIssuance.mint(initialOwner, mintAmount);
        assertEq(nativeIssuance.balanceOf(initialOwner), mintAmount);

        nativeIssuance.depositNative{value: burnAmount}(initialOwner);

        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__InvalidAmount.selector
        );
        nativeIssuance.burn(initialOwner, burnAmount + 1);
    }

    function testDepositNative() public {
        nativeIssuance.mint(initialOwner, mintAmount);
        nativeIssuance.depositNative{value: burnAmount}(initialOwner);

        assertEq(nativeIssuance.depositsForBurning(initialOwner), burnAmount);
    }

    function testDepositNativeRevertWhenAddressZero() public {
        vm.startPrank(initialOwner);
        nativeIssuance.mint(initialOwner, mintAmount);

        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__InvalidAddress.selector
        );
        nativeIssuance.depositNative{value: burnAmount}(address(0));

        assertEq(nativeIssuance.depositsForBurning(initialOwner), 0);
    }

    function testDepositNativeRevertWhenValueZero() public {
        vm.startPrank(initialOwner);
        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__InvalidAmount.selector
        );
        nativeIssuance.depositNative{value: 0}(initialOwner);

        assertEq(nativeIssuance.depositsForBurning(initialOwner), 0);
    }

    function testSetMinter() public {
        vm.startPrank(initialOwner);

        vm.expectEmit(true, true, false, true);
        emit IERC20Issuance_v1.MinterSet(minter, true);

        nativeIssuance.setMinter(minter, true);

        assertTrue(nativeIssuance.allowedMinters(minter));
    }

    function testSetMinterRevertWhenNotOwner() public {
        vm.startPrank(user);

        vm.expectRevert();

        nativeIssuance.setMinter(minter, true);
    }

    function testBalanceOf() public {
        vm.startPrank(initialOwner);
        nativeIssuance.mint(initialOwner, mintAmount);

        assertEq(nativeIssuance.balanceOf(initialOwner), mintAmount);
    }

    function testStaticMethods() public {
        assertEq(nativeIssuance.name(), "Native Issuance");
        assertEq(nativeIssuance.symbol(), "NATIVE");
        assertEq(nativeIssuance.decimals(), 18);
    }

    function testNotSupportedMethods() public {
        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__NotSupported.selector
        );
        nativeIssuance.allowance(address(0), address(0));

        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__NotSupported.selector
        );
        nativeIssuance.approve(address(0), 1);

        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__NotSupported.selector
        );
        nativeIssuance.totalSupply();

        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__NotSupported.selector
        );
        nativeIssuance.transfer(address(0), 1);

        vm.expectRevert(
            INativeIssuance_v1.INativeIssuance_v1__NotSupported.selector
        );
        nativeIssuance.transferFrom(address(0), address(0), 1);
    }

    receive() external payable {}
    fallback() external payable {}
}
