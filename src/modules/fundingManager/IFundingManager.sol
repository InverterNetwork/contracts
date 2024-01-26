// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IFundingManager {
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
    /// @param _from The address depositing tokens.
    /// @param _for The address that will receive the receipt tokens.
    /// @param _amount The amount of tokens deposited.
    event Deposit(
        address indexed _from, address indexed _for, uint indexed _amount
    );

    /// @notice Event emitted when a withdrawal takes place.
    /// @param _from The address supplying the receipt tokens.
    /// @param _for The address that will receive the underlying tokens.
    /// @param _amount The amount of underlying tokens withdrawn.
    event Withdrawal(
        address indexed _from, address indexed _for, uint indexed _amount
    );

    /// @notice Event emitted when a transferal of orchestrator tokens takes place.
    /// @param _to The address that will receive the underlying tokens.
    /// @param _amount The amount of underlying tokens transfered.
    event TransferOrchestratorToken(address indexed _to, uint indexed _amount);

    //--------------------------------------------------------------------------
    // Functions

    function token() external view returns (IERC20);

    function transferOrchestratorToken(address to, uint amount) external;
}
