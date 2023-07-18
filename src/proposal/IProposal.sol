// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IModuleManager} from "src/proposal/base/IModuleManager.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

interface IProposal is IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Proposal__CallerNotAuthorized();

    /// @notice Execution of transaction failed.
    error Proposal__ExecuteTxFailed();

    /// @notice Passed module name is invalid
    error DependencyInjection__InvalidModuleName();

    /// @notice The given module is not used in the proposal
    error DependencyInjection__ModuleNotUsedInProposal();

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

    /// @notice The version of the proposal instance.
    function version() external pure returns (string memory);

    function owner() external view returns (address);

    function manager() external view returns (address);

    /// @notice find the address of a given module using it's name in a proposal
    function findModuleAddressInProposal(string calldata moduleName)
        external
        view
        returns (address);

    /// @notice Verify whether the given address is the streaming payment processor
    function verifyAddressIsStreamingPaymentProcessor(
        address streamingPaymentProcessorAddress
    ) external view returns (bool);

    /// @notice Verify whether the given address is the simple payment processor
    function verifyAddressIsSimplePaymentProcessor(
        address simplePaymentProcessorAddress
    ) external view returns (bool);

    /// @notice Verify whether the given address is the recurring payment manager
    function verifyAddressIsRecurringPaymentManager(
        address recurringPaymentManager
    ) external view returns (bool);

    /// @notice Verify whether the given address is the milestone manager module
    function verifyAddressIsMilestoneManager(address milestoneManagerAddress)
        external
        returns (bool);

    /// @notice Verify whether the given address is the rebasing funding manager
    function verifyAddressIsRebasingFundingManager(
        address rebasingFundingManagerAddress
    ) external view returns (bool);

    /// @notice Verify whether the given address is the payment client
    function verifyAddressIsPaymentClient(address paymentClientAddress)
        external
        view
        returns (bool);

    /// @notice Verify whether the given address is the single vote governor
    function verifyAddressIsSingleVoteGovernorModule(
        address singleVoteGovernorAddress
    ) external view returns (bool);

    /// @notice Verify whether the given address is the list authorizer
    function verifyAddressIsListAuthorizerModule(address listAuthorizerAddress)
        external
        view
        returns (bool);
}
