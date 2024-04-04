// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ElasticReceiptTokenTest} from
    "test/modules/fundingManager/rebasing/abstracts/ElasticReceiptTokenTest.t.sol";

/**
 * @dev ERC20 Tests.
 */
contract ERC20 is ElasticReceiptTokenTest {
    bytes32 constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    function testApprove(address owner, address spender, uint amount)
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
    {
        // Note that an approval of zero is valid.

        vm.prank(owner);
        assertTrue(ertb.approve(spender, amount));

        assertEq(ertb.allowance(owner, spender), amount);
    }

    function testApproveInf(address owner, address spender)
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
    {
        vm.assume(owner != spender);

        mintToUser(owner, 1e9);

        vm.prank(owner);
        assertTrue(ertb.approve(spender, type(uint).max));

        vm.prank(spender);
        assertTrue(ertb.transferFrom(owner, spender, 1e9));

        assertEq(ertb.allowance(owner, spender), type(uint).max);
    }

    function testIncreaseAllowance(address owner, address spender, uint erts)
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
    {
        // Note that an allowance increase of zero is valid.

        vm.prank(owner);
        assertTrue(ertb.increaseAllowance(spender, erts));

        assertEq(ertb.allowance(owner, spender), erts);
    }

    function testDecreaseAllowance(address owner, address spender, uint erts)
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
    {
        // Note that an allowance increase/decrease of zero is valid.
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));

        vm.prank(owner);
        assertTrue(ertb.increaseAllowance(spender, erts));

        vm.prank(owner);
        assertTrue(ertb.decreaseAllowance(spender, erts));

        assertEq(ertb.allowance(owner, spender), 0);
    }

    function testTransfer(address from, address to, uint erts)
        public
        assumeTestAddress(from)
        assumeTestAddress(to)
        assumeTestAmount(erts)
    {
        mintToUser(from, erts);

        vm.prank(from);
        assertTrue(ertb.transfer(to, erts));

        if (from != to) {
            assertEq(ertb.balanceOf(from), 0);
        }
        assertEq(ertb.balanceOf(to), erts);
    }

    function testTransferAll(address from, address to, uint erts)
        public
        assumeTestAddress(from)
        assumeTestAddress(to)
        assumeTestAmount(erts)
    {
        vm.assume(from != to);

        mintToUser(from, erts);

        vm.prank(from);
        assertTrue(ertb.transferAll(to));

        assertEq(ertb.balanceOf(from), 0);
        assertEq(ertb.balanceOf(to), erts);
    }

    function testTransferFrom(address owner, address spender, uint erts)
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
        assumeTestAmount(erts)
    {
        vm.assume(owner != spender);

        mintToUser(owner, erts);

        vm.prank(owner);
        assertTrue(ertb.approve(spender, erts));

        vm.prank(spender);
        assertTrue(ertb.transferFrom(owner, spender, erts));

        assertEq(ertb.balanceOf(owner), 0);
        assertEq(ertb.balanceOf(spender), erts);
    }

    function testTransferAllFrom(address owner, address spender, uint erts)
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
        assumeTestAmount(erts)
    {
        vm.assume(owner != spender);

        mintToUser(owner, erts);

        vm.prank(owner);
        assertTrue(ertb.approve(spender, erts));

        vm.prank(spender);
        assertTrue(ertb.transferAllFrom(owner, spender));

        assertEq(ertb.balanceOf(owner), 0);
        assertEq(ertb.balanceOf(spender), erts);
    }

    function testTransferAllFromWithZeroToken(address owner, address spender)
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
    {
        vm.assume(owner != spender);

        // Create owner balance with bit amount unequal to zero but token
        // balance being zero.
        mintToUser(spender, 1e18);
        mintToUser(owner, 1);
        underlier.burn(address(ertb), 1e18);
        ertb.rebase();

        assertEq(ertb.balanceOf(owner), 0);
        assertTrue(ertb.scaledBalanceOf(owner) != 0);

        vm.prank(spender);
        try ertb.transferAllFrom(owner, spender) {
            revert();
        } catch {
            // Fails due to not having enough allowance.
        }

        vm.prank(owner);
        ertb.approve(spender, 1);

        vm.prank(spender);
        assertTrue(ertb.transferAllFrom(owner, spender));

        assertEq(ertb.allowance(owner, spender), 0);
    }

    function testFailTransferInsufficientBalance(
        address from,
        address to,
        uint erts
    )
        public
        assumeTestAddress(from)
        assumeTestAddress(to)
        assumeTestAmount(erts)
    {
        mintToUser(from, erts - 1);

        // Fails with underflow due to insufficient balance.
        vm.prank(from);
        ertb.transfer(to, erts);
    }

    function testFailTransferFromInsufficientBalance(
        address owner,
        address spender,
        uint erts
    )
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
        assumeTestAmount(erts)
    {
        mintToUser(owner, erts - 1);

        vm.prank(owner);
        ertb.approve(spender, erts);

        // Fails with underflow due to insufficient balance.
        vm.prank(spender);
        ertb.transferFrom(owner, owner, erts);
    }

    function testFailTransferFromInsufficientAllowance(
        address owner,
        address spender,
        uint erts
    )
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
        assumeTestAmount(erts)
    {
        mintToUser(owner, erts);

        vm.prank(owner);
        ertb.approve(spender, erts - 1);

        // Fails with underflow due to insufficient allowance.
        vm.prank(spender);
        ertb.transferFrom(owner, owner, erts);
    }

    function testFailTransferAllFromInsufficientAllowance(
        address owner,
        address spender,
        uint erts
    )
        public
        assumeTestAddress(owner)
        assumeTestAddress(spender)
        assumeTestAmount(erts)
    {
        mintToUser(owner, erts);

        vm.prank(owner);
        ertb.approve(spender, erts - 1);

        // Fails with underflow due to insufficient allowance.
        vm.prank(spender);
        ertb.transferFrom(owner, owner, erts);
    }

    function testPermit() public {
        uint privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ertb.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        ertb.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(ertb.allowance(owner, address(0xCAFE)), 1e18);
        assertEq(ertb.nonces(owner), 1);
    }

    function testFailPermitBadNonce() public {
        uint privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ertb.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            1,
                            block.timestamp
                        )
                    )
                )
            )
        );

        // Fails due to nonce not being strictly increasing by 1.
        ertb.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);
    }

    function testFailPermitBadDeadline() public {
        uint privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ertb.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        // Fails due to deadline being in the past.
        ertb.permit(owner, address(0xCAFE), 1e18, block.timestamp + 1, v, r, s);
    }

    function testFailPermitPastDeadline() public {
        uint privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ertb.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp - 1
                        )
                    )
                )
            )
        );

        // Fails due to deadline being in the past.
        ertb.permit(owner, address(0xCAFE), 1e18, block.timestamp - 1, v, r, s);
    }

    function testFailPermitReplay() public {
        uint privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ertb.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        ertb.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);
        // Fails due to being a replay attack.
        ertb.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);
    }
}
