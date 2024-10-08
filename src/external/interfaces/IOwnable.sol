// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @title   Ownable
 * 
 * @dev     The Ownable contract has an owner address, and provides basic authorization 
 *          control functions, this simplifies the implementation of "user permissions".
 *
 * @author  OpenZeppelin
 */
interface IOwnable {
    /// @notice The Owner of the contract.
    /// @return ownerAddress The address of the owner.
    function owner() external view returns (address ownerAddress);

    /// @notice Allows the current owner to renounce control of the contract.
    function renounceOwnership() external;

    /// @notice Allows the current owner to transfer control of the contract to a newOwner.
    /// @param  _newOwner The address to transfer ownership to.
    function transferOwnership(address _newOwner) external;
}
