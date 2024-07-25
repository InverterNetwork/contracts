// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@fm/rebasing/interfaces/IERC20Metadata.sol";

/**
 * @title Rebasing ERC20 Interface
 *
 * @dev Interface definition for Rebasing ERC20 tokens which have an "elastic"
 *      external balance and "fixed" internal balance.
 *      Each user's external balance is represented as a product of a "scalar"
 *      and the user's internal balance.
 *
 *      In regular time intervals the rebase operation updates the scalar,
 *      which increases or decreases all user balances proportionally.
 *
 *      The standard ERC20 methods are denomintaed in the elastic balance.
 *
 * @author Buttonwood Foundation
 */
interface IRebasingERC20 is IERC20Metadata {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Module__RebasingERC20__CannotSelfDeposit();

    /// @notice There is a cap on deposits.
    error Module__RebasingERC20__DepositCapReached();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a deposit takes place.
    /// @param _from The address depositing tokens.
    /// @param _for The address that will receive the receipt tokens.
    /// @param _amount The amount of tokens deposited.
    event Deposit(address indexed _from, address indexed _for, uint _amount);

    /// @notice Event emitted when a withdrawal takes place.
    /// @param _from The address supplying the receipt tokens.
    /// @param _for The address that will receive the underlying tokens.
    /// @param _amount The amount of underlying tokens withdrawn.
    event Withdrawal(address indexed _from, address indexed _for, uint _amount);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the fixed balance of the specified address.
    /// @param who The address to query.
    function scaledBalanceOf(address who) external view returns (uint);

    /// @notice Returns the total fixed supply.
    function scaledTotalSupply() external view returns (uint);

    /// @notice Transfer all of the sender's balance to a specified address.
    /// @param to The address to transfer to.
    /// @return True on success, false otherwise.
    function transferAll(address to) external returns (bool);

    /// @notice Transfer all balance tokens from one address to another.
    /// @param from The address to send tokens from.
    /// @param to The address to transfer to.
    function transferAllFrom(address from, address to)
        external
        returns (bool);

    /// @notice Triggers the next rebase, if applicable.
    function rebase() external;

    /// @notice Event emitted when the balance scalar is updated.
    /// @param epoch The number of rebases since inception.
    /// @param newScalar The new scalar.
    event Rebase(uint indexed epoch, uint newScalar);
}
