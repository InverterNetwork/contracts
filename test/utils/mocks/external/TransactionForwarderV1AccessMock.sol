// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";

contract TransactionForwarderV1AccessMock is TransactionForwarder_v1 {
    constructor(string memory name) TransactionForwarder_v1(name) {}

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
