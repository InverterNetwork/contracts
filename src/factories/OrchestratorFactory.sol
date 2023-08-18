// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {
    IOrchestratorFactory,
    IOrchestrator,
    IModule
} from "src/factories/IOrchestratorFactory.sol";
import {
    IFundingManager,
    IAuthorizer,
    IPaymentProcessor
} from "src/orchestrator/IOrchestrator.sol";
import {IModuleFactory} from "src/factories/IModuleFactory.sol";

/**
 * @title Orchestrator Factory
 *
 * @dev An immutable factory for deploying orchestrators.
 *
 * @author Inverter Network
 */
contract OrchestratorFactory is IOrchestratorFactory {
    //--------------------------------------------------------------------------
    // Immutables

    /// @inheritdoc IOrchestratorFactory
    address public immutable override target;

    /// @inheritdoc IOrchestratorFactory
    address public immutable override moduleFactory;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Maps the id to the orchestrators
    mapping(uint => address) private _orchestrators;

    /// @dev The counter of the current orchestrator id.
    /// @dev Starts counting from 1.
    uint private _orchestratorIdCounter;

    //--------------------------------------------------------------------------------
    // Modifier

    /// @notice Modifier to guarantee that the given id is valid
    modifier validOrchestratorId(uint id) {
        if (id > _orchestratorIdCounter) {
            revert OrchestratorFactory__InvalidId();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address target_, address moduleFactory_) {
        target = target_;
        moduleFactory = moduleFactory_;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IOrchestratorFactory
    function createOrchestrator(
        OrchestratorConfig memory orchestratorConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IOrchestrator) {
        address clone = Clones.clone(target);

        //Map orchestrator clone
        _orchestrators[++_orchestratorIdCounter] = clone;

        // Deploy and cache {IFundingManager} module.
        address fundingManager = IModuleFactory(moduleFactory).createModule(
            fundingManagerConfig.metadata,
            IOrchestrator(clone),
            fundingManagerConfig.configData
        );

        // Deploy and cache {IAuthorizer} module.
        address authorizer = IModuleFactory(moduleFactory).createModule(
            authorizerConfig.metadata,
            IOrchestrator(clone),
            authorizerConfig.configData
        );

        // Deploy and cache {IPaymentProcessor} module.
        address paymentProcessor = IModuleFactory(moduleFactory).createModule(
            paymentProcessorConfig.metadata,
            IOrchestrator(clone),
            paymentProcessorConfig.configData
        );

        // Deploy and cache optional modules.
        uint modulesLen = moduleConfigs.length;
        address[] memory modules = new address[](modulesLen);
        for (uint i; i < modulesLen; ++i) {
            modules[i] = IModuleFactory(moduleFactory).createModule(
                moduleConfigs[i].metadata,
                IOrchestrator(clone),
                moduleConfigs[i].configData
            );
        }

        if (orchestratorConfig.owner == address(0)) {
            revert OrchestratorFactory__OrchestratorOwnerIsInvalid();
        }

        // Initialize orchestrator.
        IOrchestrator(clone).init(
            _orchestratorIdCounter,
            orchestratorConfig.token,
            modules,
            IFundingManager(fundingManager),
            IAuthorizer(authorizer),
            IPaymentProcessor(paymentProcessor)
        );

        // Second round of module initializations to satisfy cross-referencing between modules
        // This can be run post the orchestrator initialization. This ensures a few more variables are
        // available that are set during the orchestrator init function.
        for (uint i; i < modulesLen; ++i) {
            if (_dependencyInjectionRequired(moduleConfigs[i].dependencyData)) {
                IModule(modules[i]).init2(
                    IOrchestrator(clone), moduleConfigs[i].dependencyData
                );
            }
        }

        // Also, running the init2 functionality on the compulsory modules excluded from the modules array
        if (_dependencyInjectionRequired(fundingManagerConfig.dependencyData)) {
            IModule(fundingManager).init2(
                IOrchestrator(clone), fundingManagerConfig.dependencyData
            );
        }
        if (_dependencyInjectionRequired(authorizerConfig.dependencyData)) {
            IModule(authorizer).init2(
                IOrchestrator(clone), authorizerConfig.dependencyData
            );
        }
        if (_dependencyInjectionRequired(paymentProcessorConfig.dependencyData))
        {
            IModule(paymentProcessor).init2(
                IOrchestrator(clone), paymentProcessorConfig.dependencyData
            );
        }

        return IOrchestrator(clone);
    }

    /// @inheritdoc IOrchestratorFactory
    function getOrchestratorByID(uint id)
        external
        view
        validOrchestratorId(id)
        returns (address)
    {
        return _orchestrators[id];
    }

    function getOrchestratorIDCounter() external view returns (uint) {
        return _orchestratorIdCounter;
    }

    function decoder(bytes memory data)
        public
        pure
        returns (bool requirement)
    {
        (requirement,,) = abi.decode(data, (bool, string[], bytes));
    }

    function _dependencyInjectionRequired(bytes memory dependencyData)
        internal
        view
        returns (bool)
    {
        try this.decoder(dependencyData) returns (bool) {
            return this.decoder(dependencyData);
        } catch {
            return false;
        }
    }
}
