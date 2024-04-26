// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@oz/access/Ownable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

interface IERC20Issuance_v1 {
    // Events

    /// @notice Emitted when the minter is set.
    event MinterSet(address indexed minter);

    //--------------------------------------------------------------------------
    // Errors
    error IERC20Issuance__CallerIsNotMinter();

    error IERC20Issuance__MintExceedsSupplyCap();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Sets the address of the minter.
    /// @param _minter The address of the minter.
    function setMinter(address _minter) external;

    /// @notice Mints new tokens
    /// @param _to The address of the recipient.
    /// @param _amount The amount of tokens to mint.
    function mint(address _to, uint _amount) external;

    /// @notice Burns tokens
    /// @param _from The address of the owner.
    /// @param _amount The amount of tokens to burn.
    function burn(address _from, uint _amount) external;
}
