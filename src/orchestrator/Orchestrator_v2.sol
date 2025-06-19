// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    IOrchestrator_v2,
    IGovernor_v1
} from "src/orchestrator/interfaces/IOrchestrator_v2.sol";

import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IPaymentProcessor_v2} from "@pp/IPaymentProcessor_v2.sol";
import {IPaymentProcessor_v3} from "@pp/IPaymentProcessor_v3.sol";

import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModule_v2} from "src/modules/base/IModule_v2.sol";
import {IModuleManagerBase_v1} from
    "src/orchestrator/interfaces/IModuleManagerBase_v1.sol";

// Internal Dependencies
import {ModuleManagerBase_v1} from
    "src/orchestrator/abstracts/ModuleManagerBase_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// External Libraries
import {ERC165Checker} from "@oz/utils/introspection/ERC165Checker.sol";

/**
 * @title   Inverter Orchestrator
 *
 * @dev     This Contract is the center and connecting block of all Modules in a
 *          Inverter Network Workflow. It contains references to the essential contracts
 *          that make up a workflow. By inheriting the ModuleManager it allows for managing
 *          which modules make up the workflow.
 *
 *          An orchestrator is composed of a funding mechanism
 *          and a set of modules.
 *
 *          The token being accepted for funding is non-changeable and set during
 *          initialization. Authorization is performed via calling a non-changeable
 *          {IAuthorizer_v2} instance. Payments, initiated by modules, are processed
 *          via a non-changeable {IPaymentProcessor_v3} instance.
 *
 *          Each orchestrator has a unique id set during initialization.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @author  Inverter Network
 */
contract Orchestrator_v2 is IOrchestrator_v2, ModuleManagerBase_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ModuleManagerBase_v1)
        returns (bool)
    {
        return interfaceId == type(IOrchestrator_v2).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier permissioned() {
        _checkAuthorization(_msgSender(), _msgData());
        _;
    }

    /// @dev	Modifier to guarantee that the given module is a logic module
    ///         and not the authorizer or the fundingManager or the paymentProcessor.
    /// @param  module_ The module to be checked.
    modifier onlyLogicModules(address module_) {
        // Revert given module to be removed is equal to current authorizer
        if (module_ == address(authorizer)) {
            revert Orchestrator__InvalidRemovalOfAuthorizer();
        }
        // Revert given module to be removed is equal to current fundingManager
        if (module_ == address(fundingManager)) {
            revert Orchestrator__InvalidRemovalOfFundingManager();
        }
        // Revert given module to be removed is equal to current paymentProcessor
        if (module_ == address(paymentProcessor)) {
            revert Orchestrator__InvalidRemovalOfPaymentProcessor();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IOrchestrator_v2
    uint public override(IOrchestrator_v2) orchestratorId;

    /// @inheritdoc IOrchestrator_v2
    IFundingManager_v1 public override(IOrchestrator_v2) fundingManager;

    /// @inheritdoc IOrchestrator_v2
    IAuthorizer_v2 public override(IOrchestrator_v2) authorizer;

    /// @inheritdoc IOrchestrator_v2
    IPaymentProcessor_v3 public override(IOrchestrator_v2) paymentProcessor;

    /// @inheritdoc IOrchestrator_v2
    IGovernor_v1 public override(IOrchestrator_v2) governor;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Constructor & Initializer

    constructor(address _trustedForwarder)
        ModuleManagerBase_v1(_trustedForwarder)
    {
        _disableInitializers();
    }

    /// @inheritdoc IOrchestrator_v2
    function init(
        uint orchestratorId_,
        address moduleFactory_,
        address[] calldata modules,
        IFundingManager_v1 fundingManager_,
        IAuthorizer_v2 authorizer_,
        IPaymentProcessor_v3 paymentProcessor_,
        IGovernor_v1 governor_
    ) external override(IOrchestrator_v2) initializer {
        // Initialize upstream contracts.
        __ModuleManager_init(moduleFactory_, modules);

        // Set storage variables.
        orchestratorId = orchestratorId_;

        fundingManager = fundingManager_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        governor = governor_;

        // Add necessary modules.
        // Note to not use the public addModule function as the factory
        // is (most probably) not authorized.
        {
            bytes4[] memory privilegedInterfaceIds = new bytes4[](1);
            privilegedInterfaceIds[0] = type(IFundingManager_v1).interfaceId;

            _enforcePrivilegedModuleInterfaceCheck(
                address(fundingManager_), privilegedInterfaceIds
            );
            __ModuleManager_addModule(address(fundingManager_));

            privilegedInterfaceIds = new bytes4[](2);
            privilegedInterfaceIds[0] = type(IAuthorizer_v1).interfaceId;
            privilegedInterfaceIds[1] = type(IAuthorizer_v2).interfaceId;

            _enforcePrivilegedModuleInterfaceCheck(
                address(authorizer_), privilegedInterfaceIds
            );
            __ModuleManager_addModule(address(authorizer_));

            privilegedInterfaceIds = new bytes4[](3);
            privilegedInterfaceIds[0] = type(IPaymentProcessor_v1).interfaceId;
            privilegedInterfaceIds[1] = type(IPaymentProcessor_v2).interfaceId;
            privilegedInterfaceIds[2] = type(IPaymentProcessor_v3).interfaceId;

            _enforcePrivilegedModuleInterfaceCheck(
                address(paymentProcessor_), privilegedInterfaceIds
            );
            __ModuleManager_addModule(address(paymentProcessor_));
        }

        emit OrchestratorInitialized(
            orchestratorId_,
            address(fundingManager_),
            address(authorizer_),
            address(paymentProcessor_),
            modules,
            address(governor_)
        );
    }

    //--------------------------------------------------------------------------
    // onlyOrchestratorAdmin Functions

    /// @inheritdoc IOrchestrator_v2
    function initiateSetAuthorizerWithTimelock(address newAuthorizerAddress)
        external
        permissioned
    {
        bytes4[] memory privilegedInterfaceIds = new bytes4[](2);
        privilegedInterfaceIds[0] = type(IAuthorizer_v1).interfaceId;
        privilegedInterfaceIds[1] = type(IAuthorizer_v2).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            newAuthorizerAddress, privilegedInterfaceIds
        );

        _initiateAddModuleWithTimelock(newAuthorizerAddress);
        _initiateRemoveModuleWithTimelock(address(authorizer));
    }

    /// @inheritdoc IOrchestrator_v2
    function executeSetAuthorizer(address newAuthorizerAddress)
        external
        permissioned
        updatingModuleAlreadyStarted(newAuthorizerAddress)
        timelockExpired(newAuthorizerAddress)
    {
        bytes4[] memory privilegedInterfaceIds = new bytes4[](2);
        privilegedInterfaceIds[0] = type(IAuthorizer_v1).interfaceId;
        privilegedInterfaceIds[1] = type(IAuthorizer_v2).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            newAuthorizerAddress, privilegedInterfaceIds
        );

        _executeRemoveModule(address(authorizer));

        // set timelock to inactive
        moduleAddressToTimelock[newAuthorizerAddress].timelockActive = false;
        // Use _commitAddModule directly as it doesnt need the authorization of the by now none existing Authorizer
        _commitAddModule(newAuthorizerAddress);

        authorizer = IAuthorizer_v2(newAuthorizerAddress);
        emit AuthorizerUpdated(newAuthorizerAddress);
    }

    /// @inheritdoc IOrchestrator_v2
    function cancelAuthorizerUpdate(address authorizer_)
        external
        permissioned
    {
        _cancelModuleUpdate(address(authorizer));
        _cancelModuleUpdate(authorizer_);
    }

    /// @inheritdoc IOrchestrator_v2
    function initiateSetFundingManagerWithTimelock(
        address newFundingManagerAddress
    ) external permissioned {
        bytes4[] memory privilegedInterfaceIds = new bytes4[](1);
        privilegedInterfaceIds[0] = type(IFundingManager_v1).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            newFundingManagerAddress, privilegedInterfaceIds
        );

        // Check if the token is the same as the current one
        if (
            fundingManager.token()
                != IFundingManager_v1(newFundingManagerAddress).token()
        ) {
            revert Orchestrator__MismatchedTokenForFundingManager(
                address(fundingManager.token()),
                address(IFundingManager_v1(newFundingManagerAddress).token())
            );
        } else {
            _initiateAddModuleWithTimelock(newFundingManagerAddress);
            _initiateRemoveModuleWithTimelock(address(fundingManager));
        }
    }

    /// @inheritdoc IOrchestrator_v2
    function executeSetFundingManager(address newFundingManagerAddress)
        external
        permissioned
    {
        bytes4[] memory privilegedInterfaceIds = new bytes4[](1);
        privilegedInterfaceIds[0] = type(IFundingManager_v1).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            newFundingManagerAddress, privilegedInterfaceIds
        );
        _executeRemoveModule(address(fundingManager));
        _executeAddModule(newFundingManagerAddress);
        fundingManager = IFundingManager_v1(newFundingManagerAddress);
        emit FundingManagerUpdated(newFundingManagerAddress);
    }

    /// @inheritdoc IOrchestrator_v2
    function cancelFundingManagerUpdate(address fundingManager_)
        external
        permissioned
    {
        _cancelModuleUpdate(address(fundingManager));
        _cancelModuleUpdate(fundingManager_);
    }

    /// @inheritdoc IOrchestrator_v2
    function initiateSetPaymentProcessorWithTimelock(
        address newPaymentProcessorAddress
    ) external permissioned {
        bytes4[] memory privilegedInterfaceIds = new bytes4[](3);
        privilegedInterfaceIds[0] = type(IPaymentProcessor_v1).interfaceId;
        privilegedInterfaceIds[1] = type(IPaymentProcessor_v2).interfaceId;
        privilegedInterfaceIds[2] = type(IPaymentProcessor_v3).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            newPaymentProcessorAddress, privilegedInterfaceIds
        );

        _initiateAddModuleWithTimelock(newPaymentProcessorAddress);
        _initiateRemoveModuleWithTimelock(address(paymentProcessor));
    }

    /// @inheritdoc IOrchestrator_v2
    function executeSetPaymentProcessor(address newPaymentProcessorAddress)
        external
        permissioned
    {
        bytes4[] memory privilegedInterfaceIds = new bytes4[](3);
        privilegedInterfaceIds[0] = type(IPaymentProcessor_v1).interfaceId;
        privilegedInterfaceIds[1] = type(IPaymentProcessor_v2).interfaceId;
        privilegedInterfaceIds[2] = type(IPaymentProcessor_v3).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            newPaymentProcessorAddress, privilegedInterfaceIds
        );

        _executeRemoveModule(address(paymentProcessor));
        _executeAddModule(newPaymentProcessorAddress);

        paymentProcessor = IPaymentProcessor_v3(newPaymentProcessorAddress);
        emit PaymentProcessorUpdated(newPaymentProcessorAddress);
    }

    /// @inheritdoc IOrchestrator_v2
    function cancelPaymentProcessorUpdate(address paymentProcessor_)
        external
        permissioned
    {
        _cancelModuleUpdate(address(paymentProcessor));
        _cancelModuleUpdate(paymentProcessor_);
    }

    /// @inheritdoc IOrchestrator_v2
    function initiateAddModuleWithTimelock(address module_)
        external
        permissioned
    {
        _enforceNonPrivilegedModuleInterfaceCheck(module_);
        _initiateAddModuleWithTimelock(module_);
    }

    /// @inheritdoc IOrchestrator_v2
    function executeAddModule(address module_) external permissioned {
        _enforceNonPrivilegedModuleInterfaceCheck(module_);
        _executeAddModule(module_);
    }

    /// @inheritdoc IOrchestrator_v2
    function initiateRemoveModuleWithTimelock(address module_)
        external
        onlyLogicModules(module_)
        permissioned
    {
        _initiateRemoveModuleWithTimelock(module_);
    }

    /// @inheritdoc IOrchestrator_v2
    function executeRemoveModule(address module_)
        external
        onlyLogicModules(module_)
        permissioned
    {
        _executeRemoveModule(module_);
    }

    /// @inheritdoc IOrchestrator_v2
    function cancelModuleUpdate(address module_) external permissioned {
        _enforceNonPrivilegedModuleInterfaceCheck(module_);
        _cancelModuleUpdate(module_);
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev	Only addresses authorized via the {IAuthorizer_v2} instance can manage
    ///         modules.
    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override(ModuleManagerBase_v1)
        returns (bool)
    {
        return authorizer.hasRole(authorizer.getAdminRole(), who);
    }

    // ========================================================================
    // Internal Functions

    // ------------------------------------------------------------------------
    // Internal - Authorization

    /// @notice Checks if the caller can call the function that implements the locked modifier.
    /// @param  caller_ The address of the caller.
    /// @param  data_ The data of the call.
    function _checkAuthorization(address caller_, bytes calldata data_)
        internal
        view
    {
        // If caller cannot call the function, revert.
        if (
            !authorizer.hasPermission(caller_, address(this), bytes4(data_[0:4]))
        ) {
            revert Orchestrator__NotPermissioned();
        }
    }

    // ------------------------------------------------------------------------
    // Internal - Enforce Module Interface Check

    /// @notice Enforces that the address is in fact a Module of the required type.
    /// @dev	The function reverts if the given address is not a module of the required type.
    /// @param  _contractAddr The address to be checked.
    /// @param  _privilegedInterfaceId The required interface id.
    function _enforcePrivilegedModuleInterfaceCheck(
        address _contractAddr,
        bytes4[] memory _privilegedInterfaceId
    ) internal view {
        // If address is not a module, revert
        if (
            !ERC165Checker.supportsInterface(
                _contractAddr, type(IModule_v1).interfaceId
            )
                && !ERC165Checker.supportsInterface(
                    _contractAddr, type(IModule_v2).interfaceId
                )
        ) {
            revert Orchestrator__InvalidModuleType(_contractAddr);
        }

        bool isInterfaceSupported;
        // Check if the module supports the required interface
        for (uint i = 0; i < _privilegedInterfaceId.length; i++) {
            if (
                ERC165Checker.supportsInterface(
                    _contractAddr, _privilegedInterfaceId[i]
                )
            ) {
                isInterfaceSupported = true;
                break;
            }
        }

        if (!isInterfaceSupported) {
            revert Orchestrator__InvalidModuleType(_contractAddr);
        }
    }

    /// @dev	Internal function to enforce that the given module is not a privileged module.
    /// @param  _contractAddr The address of the module to be checked.
    function _enforceNonPrivilegedModuleInterfaceCheck(address _contractAddr)
        internal
        view
    {
        if (
            // If the given address is not a module
            // If the given address is any of the following interfaces
            (
                !ERC165Checker.supportsInterface(
                    _contractAddr, type(IModule_v1).interfaceId
                )
                    && !ERC165Checker.supportsInterface(
                        _contractAddr, type(IModule_v2).interfaceId
                    )
            )
                || ERC165Checker.supportsInterface(
                    _contractAddr, type(IAuthorizer_v1).interfaceId
                )
                || ERC165Checker.supportsInterface(
                    _contractAddr, type(IAuthorizer_v2).interfaceId
                )
                || ERC165Checker.supportsInterface(
                    _contractAddr, type(IFundingManager_v1).interfaceId
                )
                || ERC165Checker.supportsInterface(
                    _contractAddr, type(IPaymentProcessor_v1).interfaceId
                )
                || ERC165Checker.supportsInterface(
                    _contractAddr, type(IPaymentProcessor_v2).interfaceId
                )
                || ERC165Checker.supportsInterface(
                    _contractAddr, type(IPaymentProcessor_v3).interfaceId
                )
        ) {
            // Then revert
            revert Orchestrator__InvalidModuleType(_contractAddr);
        }
    }

    //--------------------------------------------------------------------------
    // IERC2771Context

    /// @inheritdoc IModuleManagerBase_v1
    /// @dev	Because we want to expose the `isTrustedForwarder` function from the {ERC2771Context} Contract in the
    ///         {IOrchestrator_v2} we have to override it here as the original openzeppelin version doesnt contain an
    ///         interface that we could use to expose it.
    function isTrustedForwarder(address forwarder)
        public
        view
        virtual
        override(IModuleManagerBase_v1, ModuleManagerBase_v1)
        returns (bool)
    {
        return ModuleManagerBase_v1.isTrustedForwarder(forwarder);
    }

    /// @inheritdoc IModuleManagerBase_v1
    function trustedForwarder()
        public
        view
        virtual
        override(IModuleManagerBase_v1, ModuleManagerBase_v1)
        returns (address)
    {
        return ModuleManagerBase_v1.trustedForwarder();
    }
}
