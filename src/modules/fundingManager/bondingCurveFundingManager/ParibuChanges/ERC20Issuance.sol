// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20Issuance} from "./IERC20Issuance.sol";

// External Dependencies
import {ERC20Upgradeable} from "@oz-up/token/ERC20/ERC20Upgradeable.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

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
contract ERC20Issuance is
    IERC20Issuance,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    // TODO: hacky, make it decent looking

    // State Variables
    address public allowedMinter;

    uint public MAX_SUPPLY;

    // Modifiers
    modifier onlyMinter() {
        if (_msgSender() != allowedMinter) {
            revert IERC20Issuance__CallerIsNotMinter();
        }
        _;
    }

    function init(string memory name_, string memory symbol_, uint _MAX_SUPPLY)
        external
        initializer
    {
        __ERC20_init(name_, symbol_);
        __Ownable_init(_msgSender());
        _setMinter(_msgSender());
        MAX_SUPPLY = _MAX_SUPPLY;
    }

    /// @notice Sets the address of the minter.
    /// @param _minter The address of the minter.
    function setMinter(address _minter) external onlyOwner {
        _setMinter(_minter);
    }

    /// @notice Mints new tokens
    /// @param _to The address of the recipient.
    /// @param _amount The amount of tokens to mint.
    function mint(address _to, uint _amount) external onlyMinter {
        if (totalSupply() + _amount > MAX_SUPPLY) {
            revert("ERC20Issuance: supply cap exceeded");
        }
        _mint(_to, _amount);
    }

    /// @notice Burns tokens
    /// @param _from The address of the owner.
    /// @param _amount The amount of tokens to burn.
    function burn(address _from, uint _amount) external onlyMinter {
        _burn(_from, _amount);
    }

    function _setMinter(address _minter) internal {
        allowedMinter = _minter;
        emit minterSet(_minter);
    }
}
