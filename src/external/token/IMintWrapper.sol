// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

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
interface IMintWrapper {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when the minter is set.
    event MinterSet(address indexed minter, bool allowed);

    //--------------------------------------------------------------------------
    // Errors
    error IERC20Issuance__CallerIsNotMinter();

    //--------------------------------------------------------------------------
    // Functions

    // Write

    /// @notice Sets the minting rights of an address.
    /// @param  _minter The address of the minter.
    /// @param  _allowed If the address is allowed to mint or not.
    function setMinter(address _minter, bool _allowed) external;

    /// @notice Mints new tokens.
    /// @param  _to The address of the recipient.
    /// @param  _amount The amount of tokens to mint.
    function mint(address _to, uint _amount) external;

    /// @notice Burns tokens.
    /// @param  _from The address of the owner or approved address.
    /// @param  _amount The amount of tokens to burn.
    function burn(address _from, uint _amount) external;

    // Read

    /// @notice Mapping of allowed minters.
    /// @param  _minter The address of the minter.
    /// @return If the address is allowed to mint or not.
    function allowedMinters(address _minter) external view returns (bool);
}
