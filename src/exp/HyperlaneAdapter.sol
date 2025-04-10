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

    IMailbox public immutable mailbox;
    address public immutable remoteMinter;

    constructor(address mailbox_, address remoteMinter_) {
        require(address(mailbox_) != address(0), "Invalid mailbox");
        require(address(remoteMinter_) != address(0), "Invalid remote minter");

        mailbox = IMailbox(mailbox_);
        remoteMinter = remoteMinter_;
    }

    function sendMintMessage(
        address receiver,
        uint amount,
        uint32 targetChainId
    ) external override {
        mailbox.dispatch(
            targetChainId,
            remoteMinter.addressToBytes32(),
            TokenMessage.format(
                receiver.addressToBytes32(), amount, "INVERTER_ISSUANCE"
            )
        );
    }
}
