// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20Issuance_v1} from
    "@fm/bondingCurve/interfaces/IERC20Issuance_v1.sol";

// External Dependencies
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@oz/token/ERC20/extensions/ERC20Capped.sol";
import {Context} from "@oz/utils/Context.sol";
import {Ownable} from "@oz/access/Ownable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   ERC20 Issuance Token
 *
 * @notice  This contract creates an ERC20 token with the ability to mint and burn tokens and a
 *          supply cap.
 *
 * @dev     The contract implements functionalties for:
 *          - opening and closing the issuance of tokens.
 *          - setting and subtracting of fees, expressed in BPS and subtracted from the collateral.
 *          - calculating the issuance amount by means of an abstract function to be implemented in
 *             the downstream contract.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author Inverter Network
 */
contract ERC20Issuance_v1 is IERC20Issuance_v1, ERC20Capped, Ownable {
    // State Variables
    mapping(address => bool) public allowedMinters;
    uint8 internal _decimals;

    //------------------------------------------------------------------------------
    // Modifiers
    modifier onlyMinter() {
        if (!allowedMinters[_msgSender()]) {
            revert IERC20Issuance__CallerIsNotMinter();
        }
        _;
    }

    //------------------------------------------------------------------------------
    // Constructor

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint maxSupply_,
        address initialAdmin_
    ) ERC20(name_, symbol_) ERC20Capped(maxSupply_) Ownable(initialAdmin_) {
        _setMinter(initialAdmin_, true);
        _decimals = decimals_;
    }

    //------------------------------------------------------------------------------
    // External Functions

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IERC20Issuance_v1
    function setMinter(address _minter, bool _allowed) external onlyOwner {
        _setMinter(_minter, _allowed);
    }

    /// @inheritdoc IERC20Issuance_v1
    function mint(address _to, uint _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    /// @inheritdoc IERC20Issuance_v1
    function burn(address _from, uint _amount) external onlyMinter {
        _burn(_from, _amount);
    }

    //------------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the minting rights of an address.
    /// @param _minter The address of the minter.
    /// @param _allowed If the address is allowed to mint or not
    function _setMinter(address _minter, bool _allowed) internal {
        allowedMinters[_minter] = _allowed;
        emit MinterSet(_minter, _allowed);
    }
}
