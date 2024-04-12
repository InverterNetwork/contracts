// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract CallIntercepter is Test {
    bool isTrusted;
    bool public callShouldBreak;

    constructor() {
        isTrusted = true;
    }

    // ERC2771Context
    // @dev Because we want to expose the isTrustedForwarder function from the ERC2771Context Contract in the IOrchestrator
    // we have to override it here as the original openzeppelin version doesnt contain a interface that we could use to expose it.
    function isTrustedForwarder(address) public view virtual returns (bool) {
        return isTrusted;
    }

    function flipIsTrusted() external {
        isTrusted = !isTrusted;
    }

    function flipCallShouldBreak() external {
        callShouldBreak = !callShouldBreak;
    }

    event CallReceived(address intercepterAddress, bytes data, address sender);

    error CallReceivedButBroke(
        address intercepterAddress, bytes data, address sender
    );

    fallback(bytes calldata) external virtual returns (bytes memory) {
        if (callShouldBreak) {
            revert CallReceivedButBroke(address(this), msg.data, msg.sender);
        }
        emit CallReceived(address(this), msg.data, msg.sender);
        return (abi.encode("Call Successful"));
    }

    receive() external payable {
        revert();
    }
}
