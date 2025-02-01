// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";

// External Dependencies
import {ERC20, ERC20Capped} from "@oz/token/ERC20/extensions/ERC20Capped.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title   Inverter ERC20 Issuance Token
 *
 * @notice  This contract creates an {ERC20} token with a supply cap and a whitelist-gated functionality
 *          to mint and burn tokens.
 *
 * @dev     The contract implements functionalities for:
 *          - Managing a whitelist of allowed minters.
 *          - Minting and burning tokens by members of said whitelist.
 *          - Enforcing a supply cap on minted tokens.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author Inverter Network
 */
contract ERC20IssuanceRebasing_v1 is IERC20Issuance_v1, ERC20Capped, Ownable {
    // State Variables
    /// @dev    The mapping of allowed minters.
    mapping(address => bool) public allowedMinters;
    /// @dev    The number of decimals of the token.
    uint8 internal immutable _decimals;

    address[] public holders;
    uint public constant REBASE_AMOUNT = 1e17;

    //------------------------------------------------------------------------------
    // Modifiers

    /// @dev    Modifier to guarantee the caller is a minter.
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
        _updateHolders(_to);
    }

    /// @inheritdoc IERC20Issuance_v1
    function burn(address _from, uint _amount) external onlyMinter {
        _burn(_from, _amount);
        _updateHolders(_from);
    }

    function _update(address _from, address _to, uint _value)
        internal
        override
    {
        _updateHolders(_to);
        super._update(_from, _to, _value);
    }

    function rebase() external {
        for (uint i = 0; i < holders.length; i++) {
            address holder = holders[i];
            // For each full token we generate 0.1 tokens in the rebase
            _mint(holder, (balanceOf(holder) / 1e18) * REBASE_AMOUNT);
        }
    }

    //------------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the minting rights of an address.
    /// @param  _minter The address of the minter.
    /// @param  _allowed If the address is allowed to mint or not.
    function _setMinter(address _minter, bool _allowed) internal {
        allowedMinters[_minter] = _allowed;
        emit MinterSet(_minter, _allowed);
    }

    function _updateHolders(address holder_) internal {
        uint length = holders.length;
        for (uint i = 0; i < length; i++) {
            if (holders[i] == holder_) {
                return;
            }
        }

        holders.push(holder_);
    }
}
