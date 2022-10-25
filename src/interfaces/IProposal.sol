// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IPaymentProcessor} from "src/interfaces/IPaymentProcessor.sol";
import {IModuleManager} from "src/interfaces/IModuleManager.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IProposal is IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Proposal__CallerNotAuthorized();

    /// @notice Given {IAuthorizer} instance invalid.
    error Proposal__InvalidAuthorizer();

    /// @notice Given {IPaymentProcessor} instance invalid.
    error Proposal__InvalidPaymentProcessor();

    /// @notice Given {IERC20} instance invalid.
    error Proposal__InvalidToken();

    /// @notice Execution of transaction failed.
    error Proposal__ExecuteTxFailed();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Initialization function.
    /// @dev Note that `authorizer` and `paymentProcessor` MUST be elements of
    ///      `modules`.
    function init(
        uint proposalId,
        address[] calldata funders,
        address[] calldata modules, // @todo mp: Change to IModules.
        IAuthorizer authorizer,
        IPaymentProcessor paymentProcessor,
        IERC20 token
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

    /// @notice The {IPaymentProcessor} implementation used to process module
    ///         payments.
    function paymentProcessor() external view returns (IPaymentProcessor);

    /// @notice The {IERC20} token used for payouts.
    function token() external view returns (IERC20);

    /// @notice The version of the proposal instance.
    function version() external pure returns (string memory);
}
