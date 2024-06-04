// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    IOrchestrator_v1,
    IFundingManager_v1,
    IPaymentProcessor_v1,
    IAuthorizer_v1,
    IGovernor_v1
} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleManagerBase_v1} from
    "src/orchestrator/interfaces/IModuleManagerBase_v1.sol";

// Internal Dependencies
import {ModuleManagerBase_v1} from
    "src/orchestrator/abstracts/ModuleManagerBase_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {ERC165Checker} from "@oz/utils/introspection/ERC165Checker.sol";

/**
 * @title   Orchestrator_v1: Orchestrator v1 for Inverter Network.
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
 *          {IAuthorizer_v1} instance. Payments, initiated by modules, are processed
 *          via a non-changeable {IPaymentProcessor_v1} instance.
 *
 *          Each orchestrator has a unique id set during initialization.
 *
 * @author  Inverter Network
 */
contract Orchestrator_v1 is IOrchestrator_v1, ModuleManagerBase_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ModuleManagerBase_v1)
        returns (bool)
    {
        return interfaceId == type(IOrchestrator_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by the owner of the workflow
    ///         address.
    modifier onlyOrchestratorOwner() {
        bytes32 ownerRole = authorizer.getOwnerRole();

        if (!authorizer.hasRole(ownerRole, _msgSender())) {
            revert Orchestrator__CallerNotAuthorized(ownerRole, _msgSender());
        }
        _;
    }

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

    /// @inheritdoc IOrchestrator_v1
    uint public override(IOrchestrator_v1) orchestratorId;

    /// @inheritdoc IOrchestrator_v1
    IFundingManager_v1 public override(IOrchestrator_v1) fundingManager;

    /// @inheritdoc IOrchestrator_v1
    IAuthorizer_v1 public override(IOrchestrator_v1) authorizer;

    /// @inheritdoc IOrchestrator_v1
    IPaymentProcessor_v1 public override(IOrchestrator_v1) paymentProcessor;

    /// @inheritdoc IOrchestrator_v1
    IGovernor_v1 public override(IOrchestrator_v1) governor;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initializer

    constructor(address _trustedForwarder)
        ModuleManagerBase_v1(_trustedForwarder)
    {
        _disableInitializers();
    }

    /// @inheritdoc IOrchestrator_v1
    function init(
        uint orchestratorId_,
        address[] calldata modules,
        IFundingManager_v1 fundingManager_,
        IAuthorizer_v1 authorizer_,
        IPaymentProcessor_v1 paymentProcessor_,
        IGovernor_v1 governor_
    ) external override(IOrchestrator_v1) initializer {
        // Initialize upstream contracts.
        __ModuleManager_init(modules);

        // Set storage variables.
        orchestratorId = orchestratorId_;

        fundingManager = fundingManager_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        governor = governor_;

        // Add necessary modules.
        // Note to not use the public addModule function as the factory
        // is (most probably) not authorized.

        _enforcePrivilegedModuleInterfaceCheck(
            address(fundingManager_), type(IFundingManager_v1).interfaceId
        );
        __ModuleManager_addModule(address(fundingManager_));

        _enforcePrivilegedModuleInterfaceCheck(
            address(authorizer_), type(IAuthorizer_v1).interfaceId
        );
        __ModuleManager_addModule(address(authorizer_));

        _enforcePrivilegedModuleInterfaceCheck(
            address(paymentProcessor_), type(IPaymentProcessor_v1).interfaceId
        );
        __ModuleManager_addModule(address(paymentProcessor_));

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
    // Module search functions

    /// @notice verifies whether a orchestrator with the title `moduleName` has been used in this orchestrator
    /// @dev The query string and the module title should be **exactly** same, as in same whitespaces, same capitalizations, etc.
    /// @param moduleName Query string which is the title of the module to be searched in the orchestrator
    /// @return uint256 index of the module in the list of modules used in the orchestrator
    /// @return address address of the module with title `moduleName`
    function _isModuleUsedInOrchestrator(string calldata moduleName)
        private
        view
        returns (uint, address)
    {
        address[] memory moduleAddresses = listModules();
        uint moduleAddressesLength = moduleAddresses.length;
        string memory currentModuleName;
        uint index;

        for (; index < moduleAddressesLength;) {
            currentModuleName = IModule_v1(moduleAddresses[index]).title();

            if (bytes(currentModuleName).length == bytes(moduleName).length) {
                if (
                    keccak256(abi.encodePacked(currentModuleName))
                        == keccak256(abi.encodePacked(moduleName))
                ) {
                    return (index, moduleAddresses[index]);
                }
            }

            unchecked {
                ++index;
            }
        }

        return (type(uint).max, address(0));
    }

    /// @inheritdoc IOrchestrator_v1
    function findModuleAddressInOrchestrator(string calldata moduleName)
        external
        view
        returns (address)
    {
        (uint moduleIndex, address moduleAddress) =
            _isModuleUsedInOrchestrator(moduleName);
        if (moduleIndex == type(uint).max) {
            revert
                Orchestrator__DependencyInjection__ModuleNotUsedInOrchestrator();
        }

        return moduleAddress;
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Only addresses authorized via the {IAuthorizer_v1} instance can manage
    ///      modules.
    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override(ModuleManagerBase_v1)
        returns (bool)
    {
        return authorizer.hasRole(authorizer.getOwnerRole(), who);
    }

    //--------------------------------------------------------------------------
    // onlyOrchestratorOwner Functions

    /// @inheritdoc IOrchestrator_v1
    function initiateSetAuthorizerWithTimelock(IAuthorizer_v1 authorizer_)
        external
        onlyOrchestratorOwner
    {
        address authorizerContract = address(authorizer_);
        bytes4 authorizerInterfaceId = type(IAuthorizer_v1).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            authorizerContract, authorizerInterfaceId
        );

        _initiateAddModuleWithTimelock(authorizerContract);
        _initiateRemoveModuleWithTimelock(address(authorizer));
    }

    /// @inheritdoc IOrchestrator_v1
    function executeSetAuthorizer(IAuthorizer_v1 authorizer_)
        external
        onlyOrchestratorOwner
        updatingModuleAlreadyStarted(address(authorizer_))
        whenTimelockExpired(address(authorizer_))
    {
        _executeRemoveModule(address(authorizer));

        //set timelock to inactive
        moduleAddressToTimelock[address(authorizer_)].timelockActive = false;
        //Use _commitAddModule directly as it doesnt need the authorization of the by now none existing Authorizer
        _commitAddModule(address(authorizer_));

        authorizer = authorizer_;
        emit AuthorizerUpdated(address(authorizer_));
    }

    /// @inheritdoc IOrchestrator_v1
    function cancelAuthorizerUpdate(IAuthorizer_v1 authorizer_)
        external
        onlyOrchestratorOwner
    {
        _cancelModuleUpdate(address(authorizer_));
    }

    /// @inheritdoc IOrchestrator_v1
    function initiateSetFundingManagerWithTimelock(
        IFundingManager_v1 fundingManager_
    ) external onlyOrchestratorOwner {
        address fundingManagerContract = address(fundingManager_);
        bytes4 fundingManagerInterfaceId = type(IFundingManager_v1).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            fundingManagerContract, fundingManagerInterfaceId
        );

        if (fundingManager.token() != fundingManager_.token()) {
            revert Orchestrator__MismatchedTokenForFundingManager(
                address(fundingManager.token()),
                address(fundingManager_.token())
            );
        } else {
            _initiateAddModuleWithTimelock(fundingManagerContract);
            _initiateRemoveModuleWithTimelock(address(fundingManager));
        }
    }

    /// @inheritdoc IOrchestrator_v1
    function executeSetFundingManager(IFundingManager_v1 fundingManager_)
        external
        onlyOrchestratorOwner
    {
        _executeRemoveModule(address(fundingManager));
        _executeAddModule(address(fundingManager_));
        fundingManager = fundingManager_;
        emit FundingManagerUpdated(address(fundingManager_));
    }

    /// @inheritdoc IOrchestrator_v1
    function cancelFundingManagerUpdate(IFundingManager_v1 fundingManager_)
        external
        onlyOrchestratorOwner
    {
        _cancelModuleUpdate(address(fundingManager_));
    }

    /// @inheritdoc IOrchestrator_v1
    function initiateSetPaymentProcessorWithTimelock(
        IPaymentProcessor_v1 paymentProcessor_
    ) external onlyOrchestratorOwner {
        address paymentProcessorContract = address(paymentProcessor_);
        bytes4 paymentProcessorInterfaceId =
            type(IPaymentProcessor_v1).interfaceId;

        _enforcePrivilegedModuleInterfaceCheck(
            paymentProcessorContract, paymentProcessorInterfaceId
        );

        _initiateAddModuleWithTimelock(paymentProcessorContract);
        _initiateRemoveModuleWithTimelock(address(paymentProcessor));
    }

    /// @inheritdoc IOrchestrator_v1
    function executeSetPaymentProcessor(IPaymentProcessor_v1 paymentProcessor_)
        external
        onlyOrchestratorOwner
    {
        _executeRemoveModule(address(paymentProcessor));
        _executeAddModule(address(paymentProcessor_));
        paymentProcessor = paymentProcessor_;
        emit PaymentProcessorUpdated(address(paymentProcessor_));
    }

    /// @inheritdoc IOrchestrator_v1
    function cancelPaymentProcessorUpdate(
        IPaymentProcessor_v1 paymentProcessor_
    ) external onlyOrchestratorOwner {
        _cancelModuleUpdate(address(paymentProcessor_));
    }

    /// @inheritdoc IOrchestrator_v1
    function cancelModuleUpdate(address module_) external {
        _cancelModuleUpdate(module_);
    }

    /// @inheritdoc IOrchestrator_v1
    function initiateAddModuleWithTimelock(address module_) external {
        _initiateAddModuleWithTimelock(module_);
    }

    /// @inheritdoc IOrchestrator_v1
    function initiateRemoveModuleWithTimelock(address module_)
        external
        onlyLogicModules(module_)
    {
        _initiateRemoveModuleWithTimelock(module_);
    }

    /// @inheritdoc IOrchestrator_v1
    function executeAddModule(address module_) external {
        _executeAddModule(module_);
    }

    /// @inheritdoc IOrchestrator_v1
    function executeRemoveModule(address module_)
        external
        onlyLogicModules(module_)
    {
        _executeRemoveModule(module_);
    }

    /// @inheritdoc IOrchestrator_v1
    function executeTx(address target, bytes memory data)
        external
        onlyOrchestratorOwner
        returns (bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) = target.call(data);

        if (ok) {
            return returnData;
        } else {
            revert Orchestrator__ExecuteTxFailed();
        }
    }

    // Enforces that the address is in fact a Module of the required type
    function _enforcePrivilegedModuleInterfaceCheck(
        address _contractAddr,
        bytes4 _privilegedInterfaceId
    ) internal view {
        bytes4 moduleInterfaceId = type(IModule_v1).interfaceId;
        if (
            !ERC165Checker.supportsInterface(_contractAddr, moduleInterfaceId)
                || !ERC165Checker.supportsInterface(
                    _contractAddr, _privilegedInterfaceId
                )
        ) {
            revert Orchestrator__InvalidModuleType(_contractAddr);
        }
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IOrchestrator_v1
    function version() external pure returns (string memory) {
        return "1";
    }

    // IERC2771Context
    // @dev Because we want to expose the isTrustedForwarder function from the ERC2771Context Contract in the IOrchestrator_v1
    // we have to override it here as the original openzeppelin version doesnt contain a interface that we could use to expose it.

    function isTrustedForwarder(address forwarder)
        public
        view
        virtual
        override(IModuleManagerBase_v1, ModuleManagerBase_v1)
        returns (bool)
    {
        return ModuleManagerBase_v1.isTrustedForwarder(forwarder);
    }

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
