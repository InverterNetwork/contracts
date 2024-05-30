// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IFundingManager_v1 {
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
    event Deposit(address indexed _from, address indexed _for, uint _amount);

    /// @notice Event emitted when a withdrawal takes place.
    /// @param _from The address supplying the receipt tokens.
    /// @param _for The address that will receive the underlying tokens.
    /// @param _amount The amount of underlying tokens withdrawn.
    event Withdrawal(address indexed _from, address indexed _for, uint _amount);

    /// @notice Event emitted when a transferal of orchestrator tokens takes place.
    /// @param _to The address that will receive the underlying tokens.
    /// @param _amount The amount of underlying tokens transfered.
    event TransferOrchestratorToken(address indexed _to, uint _amount);

    //--------------------------------------------------------------------------
    // Functions

    function token() external view returns (IERC20);

    /// @notice Transfer a specified amount of Tokens to a designated receiver address.
    /// @dev This function MUST be restricted to be called only by the Orchestrator.
    /// @dev This function CAN update internal user balances to account for the new token balance
    /// @param to The address that will receive the tokens.
    /// @param amount The amount of tokens to be transfered.
    function transferOrchestratorToken(address to, uint amount) external;
}
