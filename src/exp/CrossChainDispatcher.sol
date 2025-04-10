// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

interface ICrossChainAdapter {
    function sendMintMessage(
        address receiver,
        uint amount,
        uint32 targetChainId
    ) external;
}

interface ICrossChainDispatcher {
    function dispatchMint(address receiver, uint amount, uint32 targetChainId)
        external;
}

contract CrossChainDispatcher is ICrossChainDispatcher {
    address public owner;

    mapping(uint32 => ICrossChainAdapter) public adapters;

    event AdapterRegistered(uint32 indexed chainId, address indexed adapter);

    constructor() {
        owner = msg.sender;
    }

    function registerAdapter(uint32 chainId, address adapter) external {
        // require(msg.sender == owner, "Unauthorized");
        require(address(adapter) != address(0), "Invalid adapter");
        adapters[chainId] = ICrossChainAdapter(adapter);
        emit AdapterRegistered(chainId, adapter);
    }

    function dispatchMint(address receiver, uint amount, uint32 targetChainId)
        external
    {
        ICrossChainAdapter adapter = adapters[targetChainId];
        require(
            address(adapter) != address(0), "No adapter registered for chain"
        );
        adapter.sendMintMessage(receiver, amount, targetChainId);
    }
}
