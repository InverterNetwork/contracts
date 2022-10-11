// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IModuleManager} from "src/interfaces/IModuleManager.sol";

interface IProposal is IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Proposal__CallerNotAuthorized();

    /// @notice Given authorizer address invalid.
    error Proposal__InvalidAuthorizer();

    /// @notice Execution of transaction failed.
    error Proposal__ExecuteTxFailed();

    //--------------------------------------------------------------------------
    // Functions

    function init(
        uint proposalId,
        address[] calldata funders,
        address[] calldata modules, // @todo mp: Change to IModules.
        IAuthorizer authorizer_
    ) external;

    /// @notice Executes a call on target `target` with call data `data`.
    /// @dev Only callable by authorized caller.
    /// @param target The address to call.
    /// @param data The call data.
    /// @return The return data of the call.
    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory);

    /// @notice The {IAuthorizer} implementation used to authorize addresses.
    function authorizer() external view returns (IAuthorizer);

    /// @notice The version of the proposal instance.
    function version() external pure returns (string memory);
}
