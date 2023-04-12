// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies

import {ElasticReceiptTokenUpgradeable} from
    "@elastic-receipt-token/ElasticReceiptTokenUpgradeable.sol";

import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

import {IFundingManager} from "src/proposal/base/IFundingManager.sol";

abstract contract FundingManager is
    IFundingManager,
    Initializable,
    ContextUpgradeable,
    ElasticReceiptTokenUpgradeable
{
    using Strings for uint;
    using SafeERC20 for IERC20;

    uint internal constant DEPOSIT_CAP = 100_000_000e18;

    function __FundingManager_init(uint proposalId_, IERC20 token_)
        internal
        onlyInitializing
        returns (IERC20)
    {
        string memory _id = proposalId_.toString();
        string memory _name =
            string(abi.encodePacked("Inverter Funding Token - Proposal #", _id));
        string memory _symbol = string(abi.encodePacked("IFT-", _id));
        // Initial upstream contracts.
        __ElasticReceiptToken_init(
            _name,
            _symbol,
            IERC20MetadataUpgradeable(address(token_)).decimals()
        );

        return IERC20(address(this));
    }

    /// @dev Implemented in Proposal.
    function token() public view virtual returns (IERC20);

    /// @dev Returns the current token balance as supply target.
    function _supplyTarget()
        internal
        view
        override(ElasticReceiptTokenUpgradeable)
        returns (uint)
    {
        uint tokenBalance = token().balanceOf(address(this));

        // if(tokenBalance == 0 || tokenBalance > MAX_SUPPLY) {
        //     revert Proposal__FundingManaget__TokenBalanceOutOfRange();
        // }

        return tokenBalance;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    function deposit(uint amount) external {
        _deposit(_msgSender(), _msgSender(), amount);
    }

    function depositFor(address to, uint amount) external {
        _deposit(_msgSender(), to, amount);
    }

    function withdraw(uint amount) external {
        _withdraw(_msgSender(), _msgSender(), amount);
    }

    function withdrawTo(address to, uint amount) external {
        _withdraw(_msgSender(), to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    function _deposit(address from, address to, uint amount) internal {
        //Depositing from itself with its own balance would mint tokens without increasing underlying balance.
        if (from == address(this)) {
            revert Proposal__FundingManager__CannotSelfDeposit();
        }

        if ((amount + token().balanceOf(address(this))) > DEPOSIT_CAP) {
            revert Proposal__FundingManager__DepositCapReached();
        }

        _mint(to, amount);

        token().safeTransferFrom(from, address(this), amount);

        emit Deposit(from, to, amount);
    }

    function _withdraw(address from, address to, uint amount) internal {
        amount = _burn(from, amount);

        token().safeTransfer(to, amount);

        emit Withdrawal(from, to, amount);
    }
}
