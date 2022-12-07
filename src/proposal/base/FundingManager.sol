// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {ElasticReceiptTokenUpgradeable} from
    "@elastic-receipt-token/ElasticReceiptTokenUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

abstract contract FundingManager is
    ElasticReceiptTokenUpgradeable,
    Initializable
{
    using Strings for uint;
    using SafeERC20 for IERC20;

    function __FundingManager_init(uint proposalId_, uint8 decimals_)
        internal
        onlyInitializing
    {
        string memory id = proposalId_.toString();

        __ElasticReceiptToken_init(
            string(abi.encodePacked("Inverter Funding Token - Proposal #", id)),
            string(abi.encodePacked("IFT-", id)),
            decimals_
        );
    }

    function token() public virtual returns (IERC20);

    function _supplyTarget()
        internal
        override (ElasticReceiptTokenUpgradeable)
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
