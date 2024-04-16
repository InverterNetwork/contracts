//TODO: Updte NAtspec
/// @title Bancor Virtual Supply Bonding Curve Funding Manager Contract.
/// @author Inverter Network.
/// @notice This contract enables the issuance and redeeming of tokens on a bonding curve, using
/// a virtual supply for both the token and the collateral as input. The contract makes use of the
/// Aragon's Bancor Formula contract to calculate the issuance and redeeming rates.
/// @dev This contract inherits functionalties from the contracts:
/// - BondingCurveFundingManagerBase
/// - RedeemingBondingCurveFundingManagerBase
/// - VirtualTokenSupplyBase
/// - VirtualCollateralSupplyBase
/// The contract should be used by the Orchestrator Owner to manage all the configuration fo the
/// bonding curve, e.g., the virtual supplies and reserve ratios, as well as the opening and closing
/// of the issuance and redeeming functionalities. The contract implements the formulaWrapper
/// functions enforced by the upstream contracts, using the Bancor formula to calculate the
/// issuance/redeeming rate. It also implements a function which enables direct minting of the issuance token// SPDX-License-Identifier: LGPL-3.0-only
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
    event minterSet(address indexed minter);

    // Errors
    error IERC20Issuance_v1__CallerIsNotMinter();

    error IERC20Issuance_v1__MintExceedsSupplyCap();

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
