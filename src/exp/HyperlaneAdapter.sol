// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IMailbox} from
    "../../lib/hyperlane-monorepo/solidity/contracts/interfaces/IMailbox.sol";
import {TokenMessage} from
    "../../lib/hyperlane-monorepo/solidity/contracts/token/libs/TokenMessage.sol";
import {TypeCasts} from
    "../../lib/hyperlane-monorepo/solidity/contracts/libs/TypeCasts.sol";

import {ICrossChainAdapter} from "src/exp/CrossChainDispatcher.sol";

contract HyperlaneAdapter is ICrossChainAdapter {
    using TypeCasts for address;

    error InvalidReceiver(address receiver_);
    error InvalidAmount(uint amount_);
    error InvalidTargetChainId(uint32 targetChainId_);
    error InvalidMailbox();
    error InvalidRemoteMinter();

    IMailbox public immutable _mailbox;
    address public immutable _remoteMinter;

    event SentMintMessage(
        address indexed receiver_,
        address indexed remoteMinter_,
        uint amount_,
        uint32 targetChainId_
    );

    constructor(address mailbox_, address remoteMinter_) {
        if (address(mailbox_) == address(0)) {
            revert InvalidMailbox();
        }
        if (address(remoteMinter_) == address(0)) {
            revert InvalidRemoteMinter();
        }

        _mailbox = IMailbox(mailbox_);
        _remoteMinter = remoteMinter_;
    }

    /**
     * @notice Sends a mint message to the remote minter
     * @param receiver_ The address of the receiver on the remote chain
     * @param amount_ The amount of tokens to mint
     * @param targetChainId_ The target chain ID
     */
    function sendMintMessage(
        address receiver_,
        uint amount_,
        uint32 targetChainId_
    ) external override {
        if (address(receiver_) == address(0)) {
            revert InvalidReceiver(receiver_);
        }

        if (amount_ == 0) {
            revert InvalidAmount(amount_);
        }

        if (targetChainId_ == 0) {
            revert InvalidTargetChainId(targetChainId_);
        }

        _mailbox.dispatch(
            targetChainId_,
            _remoteMinter.addressToBytes32(),
            TokenMessage.format(
                receiver_.addressToBytes32(), amount_, "INVERTER_ISSUANCE"
            )
        );

        emit SentMintMessage(receiver_, _remoteMinter, amount_, targetChainId_);
    }
}
