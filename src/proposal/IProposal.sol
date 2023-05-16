// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IModuleManager} from "src/proposal/base/IModuleManager.sol";
import {IFundingManager} from "src/modules/FundingManager/IFundingManager.sol";
import {IAuthorizer} from "src/modules/Authorizer/IAuthorizer.sol";
import {IPaymentProcessor} from
    "src/modules/PaymentProcessor/IPaymentProcessor.sol";

interface IProposal is IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Proposal__CallerNotAuthorized();

    /// @notice Execution of transaction failed.
    error Proposal__ExecuteTxFailed();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Initialization function.
    function init(
        uint proposalId,
        address owner,
        IERC20 token,
        address[] calldata modules,
        IFundingManager fundingManager,
        IAuthorizer authorizer,
        IPaymentProcessor paymentProcessor
    ) external;

    /// @notice Executes a call on target `target` with call data `data`.
    /// @dev Only callable by authorized caller.
    /// @param target The address to call.
    /// @param data The call data.
    /// @return The return data of the call.
    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory);

    /// @notice Returns the proposal's id.
    /// @dev Unique id set by the {ProposalFactory} during initialization.
    function proposalId() external view returns (uint);

    /// @notice The {IFundingManager} implementation used to hold and distribute Funds.
    function fundingManager() external view returns (IFundingManager);

    /// @notice The {IAuthorizer} implementation used to authorize addresses.
    function authorizer() external view returns (IAuthorizer);

    /// @notice The {IPaymentProcessor} implementation used to process module
    ///         payments.
    function paymentProcessor() external view returns (IPaymentProcessor);

    /// @notice The proposal's {IERC20} token accepted for fundings and used
    ///         for payments.
    function token() external view returns (IERC20);

    /// @notice The proposal's non-rebasing receipt token.
    function receiptToken() external view returns (IERC20);

    /// @notice The version of the proposal instance.
    function version() external pure returns (string memory);

    function owner() external view returns (address);

    function manager() external view returns (address);
}
