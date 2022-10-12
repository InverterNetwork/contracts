// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IPayer} from "src/interfaces/IPayer.sol";
import {IModuleManager} from "src/interfaces/IModuleManager.sol";

interface IProposal is IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Proposal__CallerNotAuthorized();

    /// @notice Given authorizer address invalid.
    error Proposal__InvalidAuthorizer();

    /// @notice Given payer address invalid.
    error Proposal__InvalidPayer();

    /// @notice Execution of transaction failed.
    error Proposal__ExecuteTxFailed();

    //--------------------------------------------------------------------------
    // Functions

    // @todo mp: Proposal::init() docs missing.

    function init(
        uint proposalId,
        address[] calldata funders,
        address[] calldata modules, // @todo mp: Change to IModules.
        IAuthorizer authorizer,
        IPayer payer
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

    /// @notice The {IPayer} implementation used to pay addresses.
    function payer() external view returns (IPayer);

    // @notice The {IERC20} token used for payments.
    //function paymentToken() external view returns (IERC20);

    /// @notice The version of the proposal instance.
    function version() external pure returns (string memory);
}
