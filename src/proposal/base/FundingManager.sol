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

import {IFundingManager} from "src/proposal/base/IFundingManager.sol";

abstract contract FundingManager is
    IFundingManager,
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

    /// @dev Implemented in Proposal.
    function token() public view virtual returns (IERC20);

    /// @dev Returns the current token balance as supply target.
    function _supplyTarget()
        internal
        view
        override (ElasticReceiptTokenUpgradeable)
        returns (uint)
    {
        return token().balanceOf(address(this));
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    function deposit(uint amount) external {
        _deposit(msg.sender, msg.sender, amount);
    }

    function depositFor(address to, uint amount) external {
        _deposit(msg.sender, to, amount);
    }

    function withdraw(uint amount) external {
        _withdraw(msg.sender, msg.sender, amount);
    }

    function withdrawTo(address to, uint amount) external {
        _withdraw(msg.sender, to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    function _deposit(address from, address to, uint amount) internal {
        _mint(to, amount);

        token().safeTransferFrom(from, address(this), amount);
    }

    function _withdraw(address from, address to, uint amount) internal {
        amount = _burn(from, amount);

        token().safeTransfer(to, amount);
    }
}
