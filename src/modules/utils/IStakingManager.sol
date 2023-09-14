// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IStakingManager {
    //--------------------------------------------------------------------------
    // Errors

    struct Stake {
        uint id;
        uint amount;
        uint timesstamp;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a deposit takes place.
    /// @param stakeId The id of the stake that was created.
    /// @param from The address depositing tokens.
    /// @param to The address that will receive the receipt tokens.
    /// @param amount The amount of tokens deposited.
    event Deposit(uint stakeId, address from, address to, uint amount);

    /// @notice Event emitted when a withdrawal takes place.
    /// @param stakeId The id of the stake that was withdrawn from.
    /// @param from The address supplying the receipt tokens.
    /// @param to The address that will receive the underlying tokens.
    /// @param amount The amount of underlying tokens withdrawn.
    event Withdrawal(uint stakeId, address from, address to, uint amount);

    //--------------------------------------------------------------------------
    // Functions

    //Getter Functions
    function token() external view returns (IERC20);

    function getTotalAmount() external view returns (uint);

    function getStakeForAddress(address addr, uint id)
        external
        view
        returns (Stake memory stake);

    function getAllStakeIdsForAddress(address addr)
        external
        view
        returns (uint[] memory stakeIds);

    //Mutating Functions

    function deposit(uint amount) external returns (uint stakeId);
    function depositFor(address to, uint amount)
        external
        returns (uint stakeId);

    function withdraw(uint stakeId, uint amount) external;
    function withdrawTo(uint stakeId, address to, uint amount) external;
}
