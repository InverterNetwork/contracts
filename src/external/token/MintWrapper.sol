// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Dependencies
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title   Inverter Mint Wrapper
 *
 * @notice  This contract is an ownable wrapper for managing the permissioning around minting rights.
 *
 * @dev     The contract implements functionalities for:
 *          - Assigning minting rights.
 *          - Revoking minting rights.
 *          - Minting tokens (if rights are assigned).
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author Inverter Network
 */
contract MintWrapper is ERC2771Context, Ownable {
    //--------------------------------------------------------------------------
    // State Variables

    /// @dev    Stores address of issuance token.
    IERC20Issuance_v1 public issuanceToken;
    /// @dev    The mapping of allowed minters.
    mapping(address => bool) public allowedMinters;

    //------------------------------------------------------------------------------
    // Modifiers

    /// @dev    Modifier to guarantee the caller is a minter.
    modifier onlyMinter() {
        if (!allowedMinters[_msgSender()]) {
            revert IERC20Issuance_v1.IERC20Issuance__CallerIsNotMinter();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor

    constructor(
        IERC20Issuance_v1 _issuanceToken,
        address _trustedForwarder,
        address _owner
    ) ERC2771Context(_trustedForwarder) Ownable(_owner) {

        issuanceToken = _issuanceToken;
    }

    //------------------------------------------------------------------------------
    // External Functions

    function decimals() public view returns (uint8) {
        return IERC20Metadata(address(issuanceToken)).decimals();
    }

    function setMinter(address _minter, bool _allowed) external onlyOwner {
        _setMinter(_minter, _allowed);
    }

    function mint(address _to, uint _amount) external onlyMinter {
        issuanceToken.mint(_to, _amount);
    }

    function burn(address _from, uint _amount) external onlyMinter {
        issuanceToken.burn(_from, _amount);
    }

    //------------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the minting rights of an address.
    /// @param  _minter The address of the minter.
    /// @param  _allowed If the address is allowed to mint or not.
    function _setMinter(address _minter, bool _allowed) internal {
        allowedMinters[_minter] = _allowed;
        emit IERC20Issuance_v1.MinterSet(_minter, _allowed);
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context

    /// Needs to be overridden, because they are imported via the Ownable as well.
    function _msgSender()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (address sender)
    {
        return ERC2771Context._msgSender();
    }

    /// Needs to be overridden, because they are imported via the Ownable as well.PI
    function _msgData()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (uint)
    {
        return ERC2771Context._contextSuffixLength();
    }
}
