// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IModuleManager} from "src/orchestrator/base/IModuleManager.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

interface IOrchestrator is IModuleManager {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Orchestrator__CallerNotAuthorized(bytes32 role, address caller);

    /// @notice Execution of transaction failed.
    error Orchestrator__ExecuteTxFailed();

    /// @notice The given module is not used in the orchestrator
    error Orchestrator__InvalidModuleType(address module);

    /// @notice The given module is not used in the orchestrator
    error DependencyInjection__ModuleNotUsedInOrchestrator();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Authorizer updated to new address.
    /// @param _address The new address.
    event AuthorizerUpdated(address indexed _address);

    /// @notice FundingManager updated to new address.
    /// @param _address The new address.
    event FundingManagerUpdated(address indexed _address);

    /// @notice PaymentProcessor updated to new address.
    /// @param _address The new address.
    event PaymentProcessorUpdated(address indexed _address);

    /// @notice Orchestrator has been initialized with the corresponding modules
    /// @param orchestratorId_ The id of the orchestrator.
    /// @param fundingManager The address of the funding manager module.
    /// @param authorizer The address of the authorizer module.
    /// @param paymentProcessor The address of the payment processor module.
    /// @param modules The addresses of the other modules used in the orchestrator.
    event OrchestratorInitialized(
        uint indexed orchestratorId_,
        address fundingManager,
        address authorizer,
        address paymentProcessor,
        address[] modules
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Initialization function.
    function init(
        uint orchestratorId,
        address[] calldata modules,
        IFundingManager fundingManager,
        IAuthorizer authorizer,
        IPaymentProcessor paymentProcessor
    ) external;

    /// @notice Replaces the current authorizer with `_authorizer`
    /// @dev Only callable by authorized caller.
    /// @param authorizer_ The address of the new authorizer module.
    function setAuthorizer(IAuthorizer authorizer_) external;

    /// @notice Replaces the current funding manager with `fundingManager_`
    /// @dev Only callable by authorized caller.
    /// @param fundingManager_ The address of the new funding manager module.
    function setFundingManager(IFundingManager fundingManager_) external;

    /// @notice Replaces the current payment processor with `paymentProcessor_`
    /// @dev Only callable by authorized caller.
    /// @param paymentProcessor_ The address of the new payment processor module.
    function setPaymentProcessor(IPaymentProcessor paymentProcessor_)
        external;

    /// @notice Executes a call on target `target` with call data `data`.
    /// @dev Only callable by authorized caller.
    /// @param target The address to call.
    /// @param data The call data.
    /// @return The return data of the call.
    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory);

    /// @notice Returns the orchestrator's id.
    /// @dev Unique id set by the {OrchestratorFactory} during initialization.
    function orchestratorId() external view returns (uint);

    /// @notice The {IFundingManager} implementation used to hold and distribute Funds.
    function fundingManager() external view returns (IFundingManager);

    /// @notice The {IAuthorizer} implementation used to authorize addresses.
    function authorizer() external view returns (IAuthorizer);

    /// @notice The {IPaymentProcessor} implementation used to process module
    ///         payments.
    function paymentProcessor() external view returns (IPaymentProcessor);

    /// @notice The version of the orchestrator instance.
    function version() external pure returns (string memory);

    /// @notice find the address of a given module using it's name in a orchestrator
    function findModuleAddressInOrchestrator(string calldata moduleName)
        external
        view
        returns (address);
}
