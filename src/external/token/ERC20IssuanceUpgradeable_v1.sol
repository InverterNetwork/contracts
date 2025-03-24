// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20Issuance_v1} from "@ex/token/interfaces/IERC20Issuance_v1.sol";

// External Dependencies
import {
    ERC20Upgradeable,
    ERC20CappedUpgradeable
} from "@oz-up/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

/**
 * @title   Inverter ERC20 Issuance Token (Upgradeable)
 *
 * @notice  An upgradeable ERC20 token implementation with a maximum supply cap
 *          and controlled minting/burning through a whitelist permission system.
 *
 * @dev     This contract implements the following key functionalities:
 *          - Role-based access control through a minter whitelist
 *          - Controlled token issuance (minting) by authorized addresses only
 *          - Controlled token redemption (burning) by authorized addresses only
 *          - Hard cap on total token supply to prevent inflation
 *          - Support for contract upgrades through OpenZeppelin's
 *            upgradeable pattern
 *
 * @custom:setup    This contract requires the following MANDATORY setup steps:
 *
 *                  Set Minter:
 *                     - Purpose: The contract needs a minter to handle token
 *                                minting and burning operations. Without this
 *                                permission, the workflow cannot mint or burn
 *                                tokens.
 *                     - How:     The owner of the contract must call the
 *                                setMinter function to authorize the Funding
 *                                Manager of the workflow
 *                     - Example: token.setMinter(fundingManagerAddress, true);
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author Inverter Network
 */
contract ERC20IssuanceUpgradeable_v1 is
    IERC20Issuance_v1,
    ERC20CappedUpgradeable,
    OwnableUpgradeable
{
    // State Variables
    // --------------------------------------------------------------------------

    /// @notice    The mapping of allowed minters.
    mapping(address => bool) public allowedMinters;
    /// @notice    The number of decimals of the token.
    uint8 internal _decimals;

    /// @notice    Storage gap for future upgrades.
    uint[50] private __gap;

    // --------------------------------------------------------------------------
    // Modifiers

    /// @dev    Modifier to guarantee the caller is a minter.
    modifier onlyMinter() {
        if (!allowedMinters[_msgSender()]) {
            revert IERC20Issuance__CallerIsNotMinter();
        }
        _;
    }

    // --------------------------------------------------------------------------
    // Initializer

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the ERC20IssuanceUpgradeable_v1 contract.
    /// @param  name_ The name of the token.
    /// @param  symbol_ The symbol of the token.
    /// @param  decimals_ The number of decimals of the token.
    /// @param  maxSupply_ The maximum supply of the token.
    function __ERC20Issuance_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint maxSupply_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Capped_init(maxSupply_);
        __Ownable_init(_msgSender());

        _decimals = decimals_;
    }

    // --------------------------------------------------------------------------
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

    /// @inheritdoc IERC20Issuance_v1
    function spendAllowance(address _from, address _spender, uint _amount)
        external
        onlyMinter
    {
        _spendAllowance(_from, _spender, _amount);
    }

    // --------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the minting rights of an address.
    /// @param  _minter The address of the minter.
    /// @param  _allowed If the address is allowed to mint or not.
    function _setMinter(address _minter, bool _allowed) internal {
        allowedMinters[_minter] = _allowed;
        emit MinterSet(_minter, _allowed);
    }
}
