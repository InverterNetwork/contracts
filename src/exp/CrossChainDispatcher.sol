// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

interface ICrossChainAdapter {
    function sendMintMessage(
        address receiver_,
        uint amount_,
        uint32 targetChainId_
    ) external;
}

interface ICrossChainDispatcher {
    function dispatchMint(
        address receiver_,
        uint amount_,
        uint32 targetChainId_
    ) external;
}

contract CrossChainDispatcher is ICrossChainDispatcher {
    address public owner;

    error Unauthorized();
    error InvalidAdapter();

    mapping(uint32 => ICrossChainAdapter) internal _adapters;

    event AdapterRegistered(uint32 indexed chainId_, address indexed adapter_);

    constructor() {
        owner = msg.sender;
    }

    function registerAdapter(uint32 chainId_, address adapter_) external {
        if (msg.sender != owner) {
            revert Unauthorized();
        }
        if (address(adapter_) == address(0)) {
            revert InvalidAdapter();
        }
        _adapters[chainId_] = ICrossChainAdapter(adapter_);

        emit AdapterRegistered(chainId_, adapter_);
    }

    function dispatchMint(
        address receiver_,
        uint amount_,
        uint32 targetChainId_
    ) external {
        ICrossChainAdapter adapter = _adapters[targetChainId_];

        if (address(adapter) == address(0)) {
            revert InvalidAdapter();
        }

        adapter.sendMintMessage(receiver_, amount_, targetChainId_);
    }
}
