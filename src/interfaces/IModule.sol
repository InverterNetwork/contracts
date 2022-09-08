// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IModule {

    /// @notice Pauses the module.
    /// @dev Only callable by authorized addresses.
    function pause() external;

    /// @notice Unpauses the module.
    /// @dev Only callable by authorized addresses.
    function unpause() external;

    /// @notice Returns whether the contract is paused.
    /// @return bool True if paused, false otherwise.
    function paused() external view returns (bool);

    // @todo mp: Extend IModule Interface.
    // function identifier() external;
    // function version() external;
}
