// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {
    TransactionForwarder_v1,
    ITransactionForwarder_v1,
    ERC2771Forwarder
} from "src/external/forwarder/TransactionForwarder_v1.sol";

import {TransactionForwarderV1AccessMock} from
    "test/utils/mocks/external/TransactionForwarderV1AccessMock.sol";

import {CallIntercepter} from "test/utils/mocks/external/CallIntercepter.sol";

contract TransactionForwarderV1Test is Test {
    // SuT
    TransactionForwarderV1AccessMock forwarder;

    event CallReceived(address intercepterAddress, bytes data, address sender);

    function setUp() public {
        forwarder =
            new TransactionForwarderV1AccessMock("TransactionForwarder_v1");
    }

    //--------------------------------------------------------------------------
    // Test: createDigest

    function testCreateDigest(
        ERC2771Forwarder.ForwardRequestData memory req,
        uint signerPrivateKey
    ) public {
        // Restrict the signerKey to a space where it still should work
        signerPrivateKey = bound(signerPrivateKey, 1, 2 ^ 128);

        // Derive signer from signerkey
        address signer = vm.addr(signerPrivateKey);

        // set from in req to be the signer
        req.from = signer;

        // Create the digest needed to create the signature
        bytes32 digest = forwarder.createDigest(req);

        // Create Signature with digest (This has to be handled by the frontend)
        vm.prank(signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Set correct signature in request
        req.signature = signature;

        (,, bool signerMatch, address signerResult) =
            forwarder.original_validate(req);

        assertTrue(signerMatch);
        assertEq(signer, signerResult);
    }

    //--------------------------------------------------------------------------
    // Test: testExecuteMulticall()

    function testExecuteMulticallFailsNoTrustedForwarder() public {
        // Create intercepter Target
        CallIntercepter intercepter = new CallIntercepter();

        // Create SingleCall
        ITransactionForwarder_v1.SingleCall memory call =
        ITransactionForwarder_v1.SingleCall(
            address(intercepter), false, abi.encode("data")
        );

        // Set up a array for the multicall
        ITransactionForwarder_v1.SingleCall[] memory calls =
            new ITransactionForwarder_v1.SingleCall[](1);
        calls[0] = call;

        // No contract is trusted forwarder
        intercepter.flipIsTrusted();

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC2771Forwarder.ERC2771UntrustfulTarget.selector,
                address(intercepter),
                address(forwarder)
            )
        );
        forwarder.executeMulticall(calls);
    }

    function testExecuteMulticallFailsWhenCallIsNotAllowedToFailAndStillFails()
        public
    {
        // Create intercepter Target
        CallIntercepter intercepter = new CallIntercepter();

        // Create SingleCall that is allowed to fail
        ITransactionForwarder_v1.SingleCall memory call1 =
        ITransactionForwarder_v1.SingleCall(
            address(intercepter), true, abi.encode("data")
        );

        // Create SingleCall that is not allowed to fail
        ITransactionForwarder_v1.SingleCall memory call2 =
        ITransactionForwarder_v1.SingleCall(
            address(intercepter), false, abi.encode("data")
        );

        // Set up a array for the multicall
        ITransactionForwarder_v1.SingleCall[] memory calls =
            new ITransactionForwarder_v1.SingleCall[](2);
        calls[0] = call1;
        calls[0] = call2;

        // Call will fail when intercepter is called
        intercepter.flipCallShouldBreak();

        vm.expectRevert(
            abi.encodeWithSelector(
                ITransactionForwarder_v1.CallFailed.selector, call2
            )
        );
        forwarder.executeMulticall(calls);
    }

    function testExecuteMulticall(uint[] memory seeds) public {
        uint amount = seeds.length;

        // test at least one Call
        vm.assume(amount > 0);

        // no need to test more than 30 simultaneously
        if (amount >= 30) {
            amount = 30;
        }

        ITransactionForwarder_v1.SingleCall[] memory calls =
            new ITransactionForwarder_v1.SingleCall[](amount);

        CallIntercepter[] memory intercepter = new CallIntercepter[](amount);

        // for each seed
        for (uint i = 0; i < amount; i++) {
            // create a call intercepter
            intercepter[i] = new CallIntercepter();
            // Create an according call for each intercepter
            calls[i] = createSingleCall(seeds[i], address(intercepter[i]));
        }

        bool[] memory shouldEmit = new bool[](amount);

        // Check for each call
        for (uint i = 0; i < amount; i++) {
            // if call is allowed to fail we wanna check if it behaves correctly in case it should fail
            if (calls[i].allowFailure) {
                // but not all should fail so we "randomize" that a bit
                if (seeds[i] % 7 == 0) {
                    intercepter[i].flipCallShouldBreak();
                    continue;
                }
            }
            // All that dont fail should later emit
            shouldEmit[i] = true;
        }

        // Check for proper events
        // Note I put this in a different section, because the flipCallShouldBreak() function triggered the expectEmit before
        for (uint i = 0; i < amount; i++) {
            if (shouldEmit[i]) {
                // In case it doesnt fail we want to receive the correct emit
                vm.expectEmit(true, true, true, true);
                emit CallReceived(
                    address(intercepter[i]),
                    abi.encodePacked(calls[i].callData, address(this)),
                    address(forwarder)
                );
            }
        }

        // execute multicall
        ITransactionForwarder_v1.Result[] memory results =
            forwarder.executeMulticall(calls);

        uint resultLength = results.length;

        // expect results to be an equal length to the amount of calls
        assertEq(amount, resultLength);

        // check if returndata is correct
        for (uint i = 0; i < resultLength; i++) {
            // if call was a success
            if (results[i].success) {
                assertEq(results[i].returnData, abi.encode("Call Successful"));
            }
            // call failed
            else {
                assertEq(
                    results[i].returnData,
                    abi.encodeWithSelector(
                        CallIntercepter.CallReceivedButBroke.selector,
                        address(intercepter[i]),
                        abi.encodePacked(calls[i].callData, address(this)),
                        address(forwarder)
                    )
                );
            }
        }
    }

    function testIsTrustedByTarget() public {
        // Note: We are not testing _isTrustedByTarget as it is just a straightup copy from openzeppelins
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function createSingleCall(uint seed, address target)
        internal
        pure
        returns (ITransactionForwarder_v1.SingleCall memory)
    {
        bool allowFailure = seed % 2 == 0;

        // Encodes seed into bytes
        bytes memory data = abi.encode("data");

        return ITransactionForwarder_v1.SingleCall(target, allowFailure, data);
    }
}
