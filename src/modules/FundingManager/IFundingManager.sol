// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IRebasingERC20} from
    "src/modules/FundingManager/token/IRebasingERC20.sol";

interface IFundingManager is IRebasingERC20 {
    //--------------------------------------------------------------------------
    // Errors

    /// @dev Invalid Address
    error Module__FundingManager__InvalidAddress();

    /// @notice Function is only callable by authorized address.
    error Module__FundingManager__CannotSelfDeposit();

    /// @notice There is a cap on deposits.
    error Module__FundingManager__DepositCapReached();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a deposit takes place.
    /// @param from The address depositing tokens.
    /// @param to The address that will receive the receipt tokens.
    /// @param amount The amount of tokens deposited.
    event Deposit(
        address indexed from, address indexed to, uint indexed amount
    );

    /// @notice Event emitted when a withdrawal takes place.
    /// @param from The address supplying the receipt tokens.
    /// @param to The address that will receive the underlying tokens.
    /// @param amount The amount of underlying tokens withdrawn.
    event Withdrawal(
        address indexed from, address indexed to, uint indexed amount
    );

    /// @notice Event emitted when a transferal of proposal tokens takes place.
    /// @param to The address that will receive the underlying tokens.
    /// @param amount The amount of underlying tokens transfered.
    event TransferProposalToken(address indexed to, uint indexed amount);

    //--------------------------------------------------------------------------
    // Functions

    function deposit(uint amount) external;
    function depositFor(address to, uint amount) external;

    function withdraw(uint amount) external;
    function withdrawTo(address to, uint amount) external;

    function transferProposalToken(address to, uint amount) external;
}
