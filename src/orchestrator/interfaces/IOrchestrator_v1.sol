// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModuleManagerBase_v1} from
    "src/orchestrator/interfaces/IModuleManagerBase_v1.sol";
import {IGovernor_v1} from "src/external/governance/interfaces/IGovernor_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IOrchestrator_v1 is IModuleManagerBase_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Orchestrator__CallerNotAuthorized(bytes32 role, address caller);

    /// @notice Execution of transaction failed.
    error Orchestrator__ExecuteTxFailed();

    /// @notice The given module is not used in the orchestrator
    error Orchestrator__InvalidModuleType(address module);

    /// @notice The token of the new funding manager is not the same as the current funding manager.
    error Orchestrator__MismatchedTokenForFundingManager(
        address currentToken, address newToken
    );

    /// @notice The given module is not used in the orchestrator
    error Orchestrator__DependencyInjection__ModuleNotUsedInOrchestrator();

    /// @notice The Authorizer can not be removed through this function.
    error Orchestrator__InvalidRemovalOfAuthorizer();

    /// @notice The FundingManager can not be removed through this function.
    error Orchestrator__InvalidRemovalOfFundingManager();

    /// @notice The PaymentProcessor can not be removed through this function.
    error Orchestrator__InvalidRemovalOfPaymentProcessor();

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

    /// @notice Orchestrator_v1 has been initialized with the corresponding modules
    /// @param orchestratorId_ The id of the orchestrator.
    /// @param fundingManager The address of the funding manager module.
    /// @param authorizer The address of the authorizer module.
    /// @param paymentProcessor The address of the payment processor module.
    /// @param modules The addresses of the other modules used in the orchestrator.
    /// @param governor The address of the governor contract used to reference protocol level interactions
    event OrchestratorInitialized(
        uint indexed orchestratorId_,
        address fundingManager,
        address authorizer,
        address paymentProcessor,
        address[] modules,
        address governor
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Initialization function.
    function init(
        uint orchestratorId,
        address[] calldata modules,
        IFundingManager_v1 fundingManager,
        IAuthorizer_v1 authorizer,
        IPaymentProcessor_v1 paymentProcessor,
        IGovernor_v1 governor
    ) external;

    /// @notice Initiates replacing the current authorizer with `_authorizer` on a timelock.
    /// @dev Only callable by authorized caller.
    /// @param authorizer_ The address of the new authorizer module.
    function initiateSetAuthorizerWithTimelock(IAuthorizer_v1 authorizer_)
        external;

    /// @notice Initiates replaces the current funding manager with `fundingManager_` on a timelock.
    /// @dev Only callable by authorized caller.
    /// @param fundingManager_ The address of the new funding manager module.
    function initiateSetFundingManagerWithTimelock(
        IFundingManager_v1 fundingManager_
    ) external;

    /// @notice Initiates replaces the current payment processor with `paymentProcessor_` on a timelock.
    /// @dev Only callable by authorized caller.
    /// @param paymentProcessor_ The address of the new payment processor module.
    function initiateSetPaymentProcessorWithTimelock(
        IPaymentProcessor_v1 paymentProcessor_
    ) external;

    /// @notice Cancels the replacement of the current authorizer with `authorizer_`.
    /// @dev Only callable by authorized caller.
    /// @param authorizer_ The address of the new authorizer module, for which the update is canceled.
    function cancelAuthorizerUpdate(IAuthorizer_v1 authorizer_) external;

    /// @notice Cancels the replacement of the current funding manager with `fundingManager_`.
    /// @dev Only callable by authorized caller.
    /// @param fundingManager_ The address of the new funding manager module, for which the update is canceled.
    function cancelFundingManagerUpdate(IFundingManager_v1 fundingManager_)
        external;

    /// @notice Cancels the replacement of the current payment processor with `paymentProcessor_`.
    /// @dev Only callable by authorized caller.
    /// @param paymentProcessor_ The address of the new payment processro module, for which the update is canceled.
    function cancelPaymentProcessorUpdate(
        IPaymentProcessor_v1 paymentProcessor_
    ) external;

    /// @notice Executes replacing the current authorizer with `_authorizer`
    /// @notice !!! IMPORTANT !!! When changing the Authorizer the current set of assigned addresses to Roles are lost. Make sure initial owners are set properly.
    /// @dev Only callable by authorized caller.
    /// @param authorizer_ The address of the new authorizer module.
    function executeSetAuthorizer(IAuthorizer_v1 authorizer_) external;

    /// @notice Executes replaces the current funding manager with `fundingManager_`
    /// @notice !!! IMPORTANT !!! When changing the FundingManager the current funds still contained in the module might not be retrievable. Make sure to clean the FundingManager properly beforehand.
    /// @dev Only callable by authorized caller.
    /// @param fundingManager_ The address of the new funding manager module.
    function executeSetFundingManager(IFundingManager_v1 fundingManager_)
        external;

    /// @notice Executes replaces the current payment processor with `paymentProcessor_`
    /// @notice !!! IMPORTANT !!! When changing the PaymentProcessor the current ongoing payment orders are lost. Make sure to resolve those payments properly beforehand.
    /// @dev Only callable by authorized caller.
    /// @param paymentProcessor_ The address of the new payment processor module.
    function executeSetPaymentProcessor(IPaymentProcessor_v1 paymentProcessor_)
        external;

    /// @notice Initiates the adding of a module to the Orchestrator on a timelock
    /// @dev Only callable by authorized address.
    /// @dev Fails of adding module exeeds max modules limit
    /// @dev Fails if address invalid or address already added as module.
    /// @param module The module address to add.
    function initiateAddModuleWithTimelock(address module) external;

    /// @notice Initiate the removal of a module from the Orchestrator on a timelock
    /// @dev Reverts if module to be removed is the current authorizer/fundingManager/paymentProcessor.
    ///         The functions specific to updating these 3 module categories should be used instead
    /// @dev Only callable by authorized address.
    /// @dev Fails if address not added as module.
    function initiateRemoveModuleWithTimelock(address module) external;

    /// @notice Adds address `module` as module.
    /// @dev Only callable by authorized address.
    /// @dev Fails if adding of module has not been initiated.
    /// @dev Fails if timelock has not been expired yet.
    /// @param module The module address to add.
    function executeAddModule(address module) external;

    /// @notice Removes address `module` as module.
    /// @dev Only callable by authorized address.
    /// @dev Fails if removing of module has not been initiated.
    /// @dev Fails if timelock has not been expired yet.
    /// @param module The module address to remove.
    function executeRemoveModule(address module) external;

    /// @notice Cancels an initiated update for a module. Can be adding or removing a module
    ///         from the Orchestrator
    /// @dev Only callable by authorized address.
    /// @dev Fails if module update has not been initiated
    function cancelModuleUpdate(address module) external;
    /// @notice Executes a call on target `target` with call data `data`.
    /// @dev Only callable by authorized caller.
    /// @param target The address to call.
    /// @param data The call data.
    /// @return The return data of the call.
    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory);

    /// @notice Returns the orchestrator's id.
    /// @dev Unique id set by the {OrchestratorFactory_v1} during initialization.
    function orchestratorId() external view returns (uint);

    /// @notice The {IFundingManager_v1} implementation used to hold and distribute Funds.
    function fundingManager() external view returns (IFundingManager_v1);

    /// @notice The {IAuthorizer_v1} implementation used to authorize addresses.
    function authorizer() external view returns (IAuthorizer_v1);

    /// @notice The {IPaymentProcessor_v1} implementation used to process module
    ///         payments.
    function paymentProcessor() external view returns (IPaymentProcessor_v1);

    /// @notice The version of the orchestrator instance.
    function version() external pure returns (string memory);

    /// @notice find the address of a given module using it's name in a orchestrator
    function findModuleAddressInOrchestrator(string calldata moduleName)
        external
        view
        returns (address);

    /// @notice The governor contract implementation used for protocol level interactions.
    function governor() external view returns (IGovernor_v1);
}
