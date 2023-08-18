// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Dependencies
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {ModuleManager} from "src/orchestrator/base/ModuleManager.sol";

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
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyOrchestratorOwner() {
        if (!authorizer.isAuthorized(_msgSender())) {
            revert Orchestrator__CallerNotAuthorized();
        }
        _;
    }

    // Once we merge the RoleAuthoirzer We can completely remove Ownable
    // as import and rely on IAuthorizer to validate owners.

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address or manager.
    modifier onlyOrchestratorOwnerOrManager() {
        if (
            !authorizer.isAuthorized(_msgSender())
                && !authorizer.hasRole(authorizer.getManagerRole(), _msgSender())
        ) {
            revert Orchestrator__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    IERC20 private _token;

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
        IERC20 token_,
        address[] calldata modules,
        IFundingManager fundingManager_,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override(IOrchestrator) initializer {
        // Initialize upstream contracts.
        __ModuleManager_init(modules);

        // Set storage variables.
        orchestratorId = orchestratorId_;

        _token = token_;

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
    /// @param moduleURL Query URL string which is the URL of the module to be searched in the orchestrator
    /// @param moduleIdentifier Query bytes32 identifier which can be used to decisively look for module addresses.
    /// @param useIdentifier true if query is to be made on basis of identifier, false if on the basis of URL
    /// @return uint256 index of the module in the list of modules used in the orchestrator
    /// @return address address of the module with title `moduleName`
    function _isModuleUsedInOrchestrator(
        string calldata moduleURL,
        bytes32 moduleIdentifier,
        bool useIdentifier
    ) private view returns (uint, address) {
        address[] memory moduleAddresses = listModules();
        uint moduleAddressesLength = moduleAddresses.length;
        bytes32 currentModuleIdentifier;
        string memory currentModuleURL;
        uint index;

        for (; index < moduleAddressesLength;) {
            if (!useIdentifier) {
                currentModuleURL = IModule(moduleAddresses[index]).url();

                if (bytes(currentModuleURL).length == bytes(moduleURL).length) {
                    if (
                        keccak256(abi.encodePacked(currentModuleURL))
                            == keccak256(abi.encodePacked(moduleURL))
                    ) {
                        return (index, moduleAddresses[index]);
                    }
                }
            } else {
                currentModuleIdentifier =
                    IModule(moduleAddresses[index]).identifier();

                if (currentModuleIdentifier == moduleIdentifier) {
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
    function findModuleAddressInOrchestrator(
        string calldata moduleURL,
        bytes32 moduleIdentifier,
        bool useIdentifier
    ) external view returns (address) {
        (uint moduleIndex, address moduleAddress) = _isModuleUsedInOrchestrator(
            moduleURL, moduleIdentifier, useIdentifier
        );
        if (moduleIndex == type(uint).max) {
            revert DependencyInjection__ModuleNotUsedInOrchestrator();
        }

        return moduleAddress;
    }

    //--------------------------------------------------------------------------
    // Module address verification functions
    // Note These set of functions are not mandatory for the functioning of the protocol, however they
    //      are provided for the convenience of the users since matching the names of the modules does not
    //      fully guarantee that the returned address is the address of the exact module the user was looking for

    /// @inheritdoc IOrchestrator
    function verifyAddressIsAuthorizerModule(address authModule)
        external
        view
        returns (bool)
    {
        IAuthorizer authorizerModule = IAuthorizer(authModule);

        try authorizerModule.isAuthorized(address(uint160(1234))) returns (bool)
        {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IOrchestrator
    function verifyAddressIsFundingManager(address fundingManagerAddress)
        external
        view
        returns (bool)
    {
        IFundingManager fundingManagerModule =
            IFundingManager(fundingManagerAddress);

        try fundingManagerModule.token() returns (IERC20) {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IOrchestrator
    function verifyAddressIsRecurringPaymentManager(
        address recurringPaymentManager
    ) external view returns (bool) {
        RecurringPaymentManager paymentManager =
            RecurringPaymentManager(recurringPaymentManager);

        try paymentManager.getEpochLength() returns (uint) {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IOrchestrator
    function verifyAddressIsPaymentProcessor(address paymentProcessorAddress)
        external
        view
        returns (bool)
    {
        IPaymentProcessor paymentProcessorModule =
            IPaymentProcessor(paymentProcessorAddress);

        try paymentProcessorModule.token() returns (IERC20) {
            return true;
        } catch {
            return false;
        }
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
        return authorizer.isAuthorized(who);
    }

    //--------------------------------------------------------------------------
    // onlyOrchestratorOwner Functions

    /// @inheritdoc IOrchestrator
    function setAuthorizer(IAuthorizer authorizer_)
        external
        onlyOrchestratorOwner
    {
        addModule(address(authorizer_));
        removeModule(address(authorizer));
        authorizer = authorizer_;
        emit AuthorizerUpdated(address(authorizer_));
    }

    /// @inheritdoc IOrchestrator
    function setFundingManager(IFundingManager fundingManager_)
        external
        onlyOrchestratorOwner
    {
        addModule(address(fundingManager_));
        removeModule(address(fundingManager));
        fundingManager = fundingManager_;
        emit FundingManagerUpdated(address(fundingManager_));
    }

    /// @inheritdoc IOrchestrator
    function setPaymentProcessor(IPaymentProcessor paymentProcessor_)
        external
        onlyOrchestratorOwner
    {
        addModule(address(paymentProcessor_));
        removeModule(address(paymentProcessor));
        paymentProcessor = paymentProcessor_;
        emit PaymentProcessorUpdated(address(paymentProcessor_));
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
    function token() public view override(IOrchestrator) returns (IERC20) {
        return _token;
    }

    /// @inheritdoc IOrchestrator
    function version() external pure returns (string memory) {
        return "1";
    }
}
