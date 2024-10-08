// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IMintWrapper} from "@ex/token/IMintWrapper.sol";
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Dependencies
import {Ownable} from "@oz/access/Ownable.sol";

/**
 * @title   Inverter Mint Wrapper
 *
 * @notice  Used as a wrapper around the {IERC20Issuance_v1} to manage the permissioning around minting rights.
 *          The additional layer is primarily used to avoid standard warnings on popular token trackers that are
 *          displayed to users when ERC20 tokens have an owner (which can be avoided by using the wrapper).
 *
 * @dev     Using the MintWrapper for a PIM Workflow results in the FundingManager returning the wrapper's address
 *          as the issuance token (`getIssuanceToken`) which can be confusing for users.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract MintWrapper is IMintWrapper, Ownable {
    //--------------------------------------------------------------------------
    // State Variables

    /// @dev    Stores address of issuance token.
    IERC20Issuance_v1 public issuanceToken;
    /// @dev    The mapping of allowed minters.
    mapping(address minter => bool allowed) public allowedMinters;

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

    constructor(IERC20Issuance_v1 _issuanceToken, address _owner)
        Ownable(_owner)
    {
        issuanceToken = _issuanceToken;
    }

    //------------------------------------------------------------------------------
    // External Functions

    /// @notice Returns the decimals of the underlying token.
    /// @return decimals The decimals of the underlying token.
    function decimals() public view returns (uint8) {
        return IERC20Metadata(address(issuanceToken)).decimals();
    }

    /// @inheritdoc IMintWrapper
    function setMinter(address _minter, bool _allowed) external onlyOwner {
        _setMinter(_minter, _allowed);
    }

    /// @inheritdoc IMintWrapper
    function mint(address _to, uint _amount) external onlyMinter {
        issuanceToken.mint(_to, _amount);
    }

    /// @inheritdoc IMintWrapper
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
}
