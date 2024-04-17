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

/// @title ERC20Issuance Token
/// @author Inverter Network.
/// @notice This contract creates an ERC20 token with the ability to mint and burn tokens and a supply cap.
/// @dev The contract implements functionalties for:
///         - Whitelisted mint and burn
///         - A supply cap
///         - Flexible decimals in initialization
contract ERC20Issuance is
    IERC20Issuance,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    // State Variables
    address public allowedMinter;
    uint public MAX_SUPPLY;
    uint8 internal _decimals;

    //------------------------------------------------------------------------------------
    // Modifiers
    modifier onlyMinter() {
        if (_msgSender() != allowedMinter) {
            revert IERC20Issuance__CallerIsNotMinter();
        }
        _;
    }

    //------------------------------------------------------------------------------------
    // Initializer

    function init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint MAX_SUPPLY_,
        address admin_
    ) external virtual initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init(admin_);
        _setMinter(admin_);
        MAX_SUPPLY = MAX_SUPPLY_;
        _decimals = decimals_;
    }

    //------------------------------------------------------------------------------------
    // External Functions

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IERC20Issuance
    function setMinter(address _minter) external onlyOwner {
        _setMinter(_minter);
    }

    /// @inheritdoc IERC20Issuance
    function mint(address _to, uint _amount) external onlyMinter {
        if (totalSupply() + _amount > MAX_SUPPLY) {
            revert IERC20Issuance__MintExceedsSupplyCap();
        }
        _mint(_to, _amount);
    }

    /// @inheritdoc IERC20Issuance
    function burn(address _from, uint _amount) external onlyMinter {
        _burn(_from, _amount);
    }

    //------------------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the address of the minter.
    /// @param _minter The address of the minter.
    function _setMinter(address _minter) internal {
        // Note to @Zitzak: Since the token should work independently, I wouldn't control that the minter is a module. Also, setting the minter to zero may be useful in some cases.
        allowedMinter = _minter;
        emit minterSet(_minter);
    }
}
