// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {TransactionForwarder} from
    "src/external/forwarder/TransactionForwarder.sol";

contract TransactionForwarderAccessMock is TransactionForwarder {
    constructor(string memory name) TransactionForwarder(name) {}

    function original_validate(ForwardRequestData calldata request)
        external
        view
        returns (
            bool isTrustedForwarder,
            bool active,
            bool signerMatch,
            address signer
        )
    {
        return _validate(request);
    }
}
