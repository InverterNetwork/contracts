// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {ElasticReceiptToken} from
    "@elastic-receipt-token/ElasticReceiptToken.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

abstract contract FundingManager is ElasticReceiptToken {
    using SafeERC20 for IERC20;

    constructor() ElasticReceiptToken("name", "symbol", uint8(18)) {}

    function token() public virtual returns (IERC20);

    function _supplyTarget()
        internal
        override (ElasticReceiptToken)
        returns (uint)
    {
        token().balanceOf(address(this));
    }

    function deposit(uint amount) external {
        // Mint token on a 1:1 basis to caller.
        _mint(msg.sender, amount);

        // Fetch deposit from caller.
        token().safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) external {
        _burn(msg.sender, amount);

        token().safeTransfer(msg.sender, amount);
    }
}
