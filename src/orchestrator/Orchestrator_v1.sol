// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    IOrchestrator_v1,
    IFundingManager_v1,
    IPaymentProcessor,
    IAuthorizer
} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleManagerBase_v1} from
    "src/orchestrator/interfaces/IModuleManagerBase_v1.sol";

// Internal Dependencies
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {ModuleManagerBase_v1} from
    "src/orchestrator/abstracts/ModuleManagerBase_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {ERC165Checker} from "@oz/utils/introspection/ERC165Checker.sol";

/**
 * @title   Orchestrator V1
 *
 * @dev     A new funding primitive to enable multiple actors within a decentralized
 *          network to collaborate on orchestrators.
 *
 *          An orchestrator is composed of a [funding mechanism](./base/FundingVault)
 *          and a set of [modules](./base/ModuleManagerBase_v1).
 *
 *          The token being accepted for funding is non-changeable and set during
 *          initialization. Authorization is performed via calling a non-changeable
 *          {IAuthorizer} instance. Payments, initiated by modules, are processed
 *          via a non-changeable {IPaymentProcessor} instance.
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
            revert Orchestrator_v1__CallerNotAuthorized(ownerRole, _msgSender());
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
    IAuthorizer public override(IOrchestrator_v1) authorizer;

    /// @inheritdoc IOrchestrator_v1
    IPaymentProcessor public override(IOrchestrator_v1) paymentProcessor;

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
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override(IOrchestrator_v1) initializer {
        // Initialize upstream contracts.
        __ModuleManager_init(modules);

        // Set storage variables.
        orchestratorId = orchestratorId_;

        fundingManager = fundingManager_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        // Add necessary modules.
        // Note to not use the public addModule function as the factory
        // is (most probably) not authorized.
        __ModuleManager_addModule(address(fundingManager_));
        __ModuleManager_addModule(address(authorizer_));
        __ModuleManager_addModule(address(paymentProcessor_));

        emit OrchestratorInitialized(
            orchestratorId_,
            address(fundingManager_),
            address(authorizer_),
            address(paymentProcessor_),
            modules
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
                Orchestrator_v1__DependencyInjection__ModuleNotUsedInOrchestrator();
        }

        return moduleAddress;
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Only addresses authorized via the {IAuthorizer} instance can manage
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
    function setAuthorizer(IAuthorizer authorizer_)
        external
        onlyOrchestratorOwner
    {
        address authorizerContract = address(authorizer_);
        bytes4 moduleInterfaceId = type(IModule_v1).interfaceId;
        bytes4 authorizerInterfaceId = type(IAuthorizer).interfaceId;
        if (
            ERC165Checker.supportsInterface(
                authorizerContract, moduleInterfaceId
            )
                && ERC165Checker.supportsInterface(
                    authorizerContract, authorizerInterfaceId
                )
        ) {
            addModule(address(authorizer_));
            removeModule(address(authorizer));
            authorizer = authorizer_;
            emit AuthorizerUpdated(address(authorizer_));
        } else {
            revert Orchestrator_v1__InvalidModuleType(address(authorizer_));
        }
    }

    /// @inheritdoc IOrchestrator_v1
    function setFundingManager(IFundingManager_v1 fundingManager_)
        external
        onlyOrchestratorOwner
    {
        address fundingManagerContract = address(fundingManager_);
        bytes4 moduleInterfaceId = type(IModule_v1).interfaceId;
        bytes4 fundingManagerInterfaceId = type(IFundingManager_v1).interfaceId;
        if (
            ERC165Checker.supportsInterface(
                fundingManagerContract, moduleInterfaceId
            )
                && ERC165Checker.supportsInterface(
                    fundingManagerContract, fundingManagerInterfaceId
                )
        ) {
            addModule(address(fundingManager_));
            removeModule(address(fundingManager));
            fundingManager = fundingManager_;
            emit FundingManagerUpdated(address(fundingManager_));
        } else {
            revert Orchestrator_v1__InvalidModuleType(address(fundingManager_));
        }
    }

    /// @inheritdoc IOrchestrator_v1
    function setPaymentProcessor(IPaymentProcessor paymentProcessor_)
        external
        onlyOrchestratorOwner
    {
        address paymentProcessorContract = address(paymentProcessor_);
        bytes4 moduleInterfaceId = type(IModule_v1).interfaceId;
        bytes4 paymentProcessorInterfaceId = type(IPaymentProcessor).interfaceId;
        if (
            ERC165Checker.supportsInterface(
                paymentProcessorContract, moduleInterfaceId
            )
                && ERC165Checker.supportsInterface(
                    paymentProcessorContract, paymentProcessorInterfaceId
                )
        ) {
            addModule(address(paymentProcessor_));
            removeModule(address(paymentProcessor));
            paymentProcessor = paymentProcessor_;
            emit PaymentProcessorUpdated(address(paymentProcessor_));
        } else {
            revert Orchestrator_v1__InvalidModuleType(
                address(paymentProcessor_)
            );
        }
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
            revert Orchestrator_v1__ExecuteTxFailed();
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
