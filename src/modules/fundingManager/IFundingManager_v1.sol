// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IFundingManager_v1 {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a transferal of orchestrator tokens takes place.
    /// @param _to The address that will receive the underlying tokens.
    /// @param _amount The amount of underlying tokens transfered.
    event TransferOrchestratorToken(address indexed _to, uint _amount);

    /// @notice Event emitted when collateral token has been set.
    /// @param token The token that serves as collateral token making up the curve's reserve.
    event OrchestratorTokenSet(address indexed token, uint8 decimals);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the token.
    /// @return The token.
    function token() external view returns (IERC20);

    /// @notice Transfer a specified amount of Tokens to a designated receiver address.
    /// @dev This function MUST be restricted to be called only by the Orchestrator.
    /// @dev This function CAN update internal user balances to account for the new token balance.
    /// @param to The address that will receive the tokens.
    /// @param amount The amount of tokens to be transfered.
    function transferOrchestratorToken(address to, uint amount) external;
}
