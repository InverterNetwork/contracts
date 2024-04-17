// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@oz/access/Ownable.sol";

// External Dependencies
import {ERC20Upgradeable} from "@oz-up/token/ERC20/ERC20Upgradeable.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Bonding Curve Funding Manager Base Contract.
/// @author Inverter Network.
/// @notice This contract enables the base functionalities for issuing tokens along a bonding curve.
/// @dev The contract implements functionalties for:
///         - opening and closing the issuance of tokens.
///         - setting and subtracting of fees, expressed in BPS and subtracted from the collateral.
///         - calculating the issuance amount by means of an abstract function to be implemented in
///             the downstream contract.
interface IERC20Issuance_v1 {
    // Events

    /// @notice Emitted when the minter is set.
    event minterSet(address indexed minter);

    //--------------------------------------------------------------------------
    // Errors
    error IERC20Issuance_v1__CallerIsNotMinter();

    error IERC20Issuance_v1__MintExceedsSupplyCap();

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
