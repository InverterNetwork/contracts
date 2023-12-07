// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {ModuleManager} from "src/orchestrator/base/ModuleManager.sol";

// Internal Libraries
import {LibInterfaceId} from "src/modules/lib/LibInterfaceId.sol";

// Internal Interfaces
import {
    IOrchestrator,
    IFundingManager,
    IPaymentProcessor,
    IAuthorizer
} from "src/orchestrator/IOrchestrator.sol";
import {IModule} from "src/modules/base/IModule.sol";

/**
 * @title Orchestrator
 *
 * @dev A new funding primitive to enable multiple actors within a decentralized
 *      network to collaborate on orchestrators.
 *
 *      A orchestrator is composed of a [funding mechanism](./base/FundingVault) *      and a set of [modules](./base/ModuleManager).
 *
 *      The token being accepted for funding is non-changeable and set during
 *      initialization. Authorization is performed via calling a non-changeable
 *      {IAuthorizer} instance. Payments, initiated by modules, are processed
 *      via a non-changeable {IPaymentProcessor} instance.
 *
 *      Each orchestrator has a unique id set during initialization.
 *
 * @author Inverter Network
 */
contract Orchestrator is IOrchestrator, ModuleManager {

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ModuleManager)
        returns (bool)
    {
        bytes4 interfaceId_IOrchestrator = type(IOrchestrator).interfaceId;
        return interfaceId == interfaceId_IOrchestrator
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

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IOrchestrator
    uint public override(IOrchestrator) orchestratorId;

    /// @inheritdoc IOrchestrator
    IFundingManager public override(IOrchestrator) fundingManager;

    /// @inheritdoc IOrchestrator
    IAuthorizer public override(IOrchestrator) authorizer;

    /// @inheritdoc IOrchestrator
    IPaymentProcessor public override(IOrchestrator) paymentProcessor;

    //--------------------------------------------------------------------------
    // Initializer

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IOrchestrator
    function init(
        uint orchestratorId_,
        address[] calldata modules,
        IFundingManager fundingManager_,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override(IOrchestrator) initializer {
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
            currentModuleName = IModule(moduleAddresses[index]).title();

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

    /// @inheritdoc IOrchestrator
    function findModuleAddressInOrchestrator(string calldata moduleName)
        external
        view
        returns (address)
    {
        (uint moduleIndex, address moduleAddress) =
            _isModuleUsedInOrchestrator(moduleName);
        if (moduleIndex == type(uint).max) {
            revert DependencyInjection__ModuleNotUsedInOrchestrator();
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
        override(ModuleManager)
        returns (bool)
    {
        return authorizer.hasRole(authorizer.getOwnerRole(), who);
    }

    //--------------------------------------------------------------------------
    // onlyOrchestratorOwner Functions

    /// @inheritdoc IOrchestrator
    function setAuthorizer(IAuthorizer authorizer_)
        external
        onlyOrchestratorOwner
    {
        address authorizerContract = address(authorizer_);
        bytes4 moduleInterfaceId = LibInterfaceId.getInterfaceId_IModule();
        bytes4 authorizerInterfaceId =
            LibInterfaceId.getInterfaceId_IAuthorizer();
        if (
            _supportsInterfaceHelper(authorizerContract, moduleInterfaceId)
                && _supportsInterfaceHelper(
                    authorizerContract, authorizerInterfaceId
                )
        ) {
            addModule(address(authorizer_));
            removeModule(address(authorizer));
            authorizer = authorizer_;
            emit AuthorizerUpdated(address(authorizer_));
        } else {
            revert Orchestrator__InvalidModuleType(address(authorizer_));
        }
    }

    /// @inheritdoc IOrchestrator
    function setFundingManager(IFundingManager fundingManager_)
        external
        onlyOrchestratorOwner
    {
        address fundingManagerContract = address(fundingManager_);
        bytes4 moduleInterfaceId = LibInterfaceId.getInterfaceId_IModule();
        bytes4 fundingManagerInterfaceId =
            LibInterfaceId.getInterfaceId_IFundingManager();
        if (
            _supportsInterfaceHelper(fundingManagerContract, moduleInterfaceId)
                && _supportsInterfaceHelper(
                    fundingManagerContract, fundingManagerInterfaceId
                )
        ) {
            addModule(address(fundingManager_));
            removeModule(address(fundingManager));
            fundingManager = fundingManager_;
            emit FundingManagerUpdated(address(fundingManager_));
        } else {
            revert Orchestrator__InvalidModuleType(address(fundingManager_));
        }
    }

    /// @inheritdoc IOrchestrator
    function setPaymentProcessor(IPaymentProcessor paymentProcessor_)
        external
        onlyOrchestratorOwner
    {
        address paymentProcessorContract = address(paymentProcessor_);
        bytes4 moduleInterfaceId = LibInterfaceId.getInterfaceId_IModule();
        bytes4 paymentProcessorInterfaceId =
            LibInterfaceId.getInterfaceId_IPaymentProcessor();
        if (
            _supportsInterfaceHelper(
                paymentProcessorContract, moduleInterfaceId
            )
                && _supportsInterfaceHelper(
                    paymentProcessorContract, paymentProcessorInterfaceId
                )
        ) {
            addModule(address(paymentProcessor_));
            removeModule(address(paymentProcessor));
            paymentProcessor = paymentProcessor_;
            emit PaymentProcessorUpdated(address(paymentProcessor_));
        } else {
            revert Orchestrator__InvalidModuleType(address(paymentProcessor_));
        }
    }

    function _supportsInterfaceHelper(
        address _contractAddress,
        bytes4 _interfaceId
    ) private returns (bool) {
        require(
            _contractAddress.code.length != 0,
            "Contract Address need to passed here"
        );

        (bool success, bytes memory data) = _contractAddress.call(
            abi.encodeWithSignature("supportsInterface(bytes4)", _interfaceId)
        );

        return success && abi.decode(data, (bool));
    }

    /// @inheritdoc IOrchestrator
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

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IOrchestrator
    function version() external pure returns (string memory) {
        return "1";
    }
}
