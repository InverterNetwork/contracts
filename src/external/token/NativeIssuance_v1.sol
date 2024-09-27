// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {Ownable} from "@oz/access/Ownable.sol";
import {Address} from "@oz/utils/Address.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

import {INativeMinter} from "@ex/token/INativeMinter.sol";
import {INativeIssuance_v1} from "@ex/token/INativeIssuance_v1.sol";

/**
 * @title    Native Token Issuance
 * @notice   This contract facilitates the issuance of native tokens on Avalanche L1s. It is designed to be used only by whitelisted minters, ensuring controlled token creation and destruction.
 * @dev      The contract adheres to the ERC20 standard for interoperability with Inverter Network contracts.
 *               - Maintains a list of allowed minters for managing who can call mint and burn functions.
 *               - Allows minting and burning of tokens by members of this whitelist.
 *               - Mints native tokens through Avalanche Subnet-EVM's Precompiled Native Minter contract.
 *               - Tokens burned are transferred to a designated burn address, with no recovery option for these tokens.
 *               - The `depositNative` function is used to deposit native tokens into the contract, which can then be burned by calling the `burn` function to send them to the burn address.
 * @author Inverter Network
 */
contract NativeIssuance_v1 is INativeIssuance_v1, IERC20Metadata, Ownable {
    using Address for address payable;

    /**
     * @notice The address of the native minter precompile.
     */
    INativeMinter public constant NATIVE_MINTER =
        INativeMinter(0x0200000000000000000000000000000000000001);

    /**
     * @notice The address where native tokens are sent in order to be burned for the bonding curve.
     *
     * @dev This address was chosen arbitrarily.
     */
    address public constant BURNED_FOR_BONDINGCURVE_ADDRESS =
        0x0100000000000000000000000000000000010203;

    // State Variables

    /**
     * @notice Total number of tokens minted by this contract through the native minter precompile.
     */
    uint public totalMinted;

    /**
     * @notice Mapping of the amount of native tokens deposited for burning by an address.
     */
    mapping(address => uint) public depositsForBurning;

    /// @dev    The mapping of allowed minters.
    mapping(address => bool) public allowedMinters;

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
    constructor(address initialOwner) Ownable(initialOwner) {
        _setMinter(initialOwner, true);
    }

    receive() external payable {}
    fallback() external payable {}

    /**
     * @notice Mints native tokens to the specified address.
     * @param  to   The address that will receive the minted tokens.
     * @param  amount   The number of tokens to be minted.
     */
    function mint(address to, uint amount) external override onlyMinter {
        if (to == address(0)) {
            revert INativeIssuance_v1__InvalidAddress();
        }
        // require(amount > 0, "Amount must be greater than zero");

        emit Minted(to, amount);

        totalMinted += amount;

        // Calls NativeMinter precompile through INativeMinter interface.
        NATIVE_MINTER.mintNativeCoin(to, amount);
    }

    /**
     * @notice Deposits native tokens to be able to burn native tokens from the specified address.
     * @dev    `msg.value` is the amount of native tokens to be deposited.
     * @param  from   The address that will have native tokens deposited for.
     */
    function depositNative(address from) external payable {
        if (from == address(0)) {
            revert INativeIssuance_v1__InvalidAddress();
        }

        if (msg.value == 0) {
            revert INativeIssuance_v1__InvalidAmount();
        }

        depositsForBurning[from] += msg.value;
    }

    /**
     * @notice Burns native tokens from the specified address.
     * @param  from   The address that will have tokens burned.
     * @param  amount   The number of tokens to be burned.
     */
    function burn(address from, uint amount) external override onlyMinter {
        if (from == address(0)) {
            revert INativeIssuance_v1__InvalidAddress();
        }

        if (depositsForBurning[from] < amount) {
            revert INativeIssuance_v1__InvalidAmount();
        }

        emit Burned(from, amount);

        depositsForBurning[from] -= amount;

        payable(BURNED_FOR_BONDINGCURVE_ADDRESS).sendValue(amount);
    }

    /**
     * @notice Sets the minting rights of an address.
     * @param  minter The address of the minter.
     * @param  allowed If the address is allowed to mint or not.
     */
    function setMinter(address minter, bool allowed) external onlyOwner {
        _setMinter(minter, allowed);
    }

    /**
     * @notice Returns the total supply of native tokens minted by this contract and subtracs the balance of burned address.
     */
    function totalNativeAssetSupply() external view returns (uint) {
        uint burned = BURNED_FOR_BONDINGCURVE_ADDRESS.balance;

        return totalMinted - burned;
    }

    /**
     * @notice Returns the balance of a given account.
     * @param  account The address to query the balance of.
     */
    function balanceOf(address account) external view returns (uint) {
        return account.balance;
    }

    /**
     * @notice Returns the name of the token.
     */
    function name() external pure returns (string memory) {
        return "Native Issuance";
    }

    /**
     * @notice Returns the symbol of the token.
     */
    function symbol() external pure returns (string memory) {
        return "NATIVE";
    }

    /**
     * @notice Returns the number of decimals used.
     */
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /**
     * @notice allowance is not supported
     */
    function allowance(address, /* owner */ address /* spender */ )
        external
        pure
        returns (uint)
    {
        revert INativeIssuance_v1__NotSupported();
    }

    /**
     * @notice approve is not supported
     */
    function approve(address, /* spender */ uint /* value */ )
        external
        pure
        returns (bool)
    {
        revert INativeIssuance_v1__NotSupported();
    }

    function totalSupply() external pure returns (uint) {
        revert INativeIssuance_v1__NotSupported();
    }

    /**
     * @notice transfer is not supported
     */
    function transfer(address, /* to */ uint /* value */ )
        external
        pure
        returns (bool)
    {
        revert INativeIssuance_v1__NotSupported();
    }

    /**
     * @notice transferFrom is not supported
     */
    function transferFrom(
        address, /* from */
        address, /* to */
        uint /* value */
    ) external pure returns (bool) {
        revert INativeIssuance_v1__NotSupported();
    }

    //------------------------------------------------------------------------------
    // Internal Functions

    /**
     * @notice Sets the minting rights of an address.
     * @param  _minter The address of the minter.
     * @param  _allowed If the address is allowed to mint or not.
     */
    function _setMinter(address _minter, bool _allowed) internal {
        emit MinterSet(_minter, _allowed);
        allowedMinters[_minter] = _allowed;
    }
}
