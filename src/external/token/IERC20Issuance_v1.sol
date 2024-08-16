// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IERC20Issuance_v1 is IERC20 {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when the minter is set.
    event MinterSet(address indexed minter, bool allowed);

    //--------------------------------------------------------------------------
    // Errors
    error IERC20Issuance__CallerIsNotMinter();

    //--------------------------------------------------------------------------
    // Functions

    // Write

    /// @notice Sets the minting rights of an address.
    /// @param  _minter The address of the minter.
    /// @param  _allowed If the address is allowed to mint or not.
    function setMinter(address _minter, bool _allowed) external;

    /// @notice Mints new tokens.
    /// @param  _to The address of the recipient.
    /// @param  _amount The amount of tokens to mint.
    function mint(address _to, uint _amount) external;

    /// @notice Burns tokens.
    /// @param  _from The address of the owner or approved address.
    /// @param  _amount The amount of tokens to burn.
    function burn(address _from, uint _amount) external;

    // Read

    /// @notice Mapping of allowed minters.
    /// @param  _minter The address of the minter.
    /// @return If the address is allowed to mint or not.
    function allowedMinters(address _minter) external view returns (bool);
}
