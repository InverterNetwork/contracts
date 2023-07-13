// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IAuthorizer {
    /// @notice Returns if an address is authorized to perform a specific action
    /// @param who The adress to be checked.
    function isAuthorized(address who) external view returns (bool);
}
