// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    IModule_v1
} from "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {
    IFundingManager_v1,
    IAuthorizer_v1,
    IPaymentProcessor_v1
} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModuleFactory_v1} from "src/factories/interfaces/IModuleFactory_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

//External Dependencies
import {ERC2771Context} from "@oz/metatx/ERC2771Context.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

/**
 * @title   OrchestratorFactory_v1: Orchestrator Factory v1 for the Inverter Network
 *
 * @notice  {OrchestratorFactory_v1} facilitates the deployment of orchestrators and their
 *          associated modules for the Inverter Network, ensuring seamless creation and
 *          configuration of various components in a single transaction.
 *
 * @dev     Utilizes {ERC2771Context} for meta-transaction capabilities and {ERC165} for interface
 *          detection. Orchestrators are deployed through EIP-1167 minimal proxies for efficiency.
 *          Integrates with the module factory to instantiate necessary modules with custom
 *          configurations, supporting complex setup with interdependencies among modules.
 *
 * @author  Inverter Network.
 */
contract OrchestratorFactory_v1 is
    IOrchestratorFactory_v1,
    ERC2771Context,
    ERC165
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IOrchestratorFactory_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Immutables

    /// @inheritdoc IOrchestratorFactory_v1
    address public immutable override target;

    /// @inheritdoc IOrchestratorFactory_v1
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
            revert OrchestratorFactory_v1__InvalidId();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor

    constructor(
        address target_,
        address moduleFactory_,
        address _trustedForwarder
    ) ERC2771Context(_trustedForwarder) {
        target = target_;
        moduleFactory = moduleFactory_;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IOrchestratorFactory_v1
    function createOrchestrator(
        OrchestratorConfig memory orchestratorConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IOrchestrator_v1) {
        address clone = Clones.clone(target);

        //Map orchestrator clone
        _orchestrators[++_orchestratorIdCounter] = clone;

        // Deploy and cache {IFundingManager_v1} module.
        address fundingManager = IModuleFactory_v1(moduleFactory).createModule(
            fundingManagerConfig.metadata,
            IOrchestrator_v1(clone),
            fundingManagerConfig.configData
        );

        // Deploy and cache {IAuthorizer_v1} module.
        address authorizer = IModuleFactory_v1(moduleFactory).createModule(
            authorizerConfig.metadata,
            IOrchestrator_v1(clone),
            authorizerConfig.configData
        );

        // Deploy and cache {IPaymentProcessor_v1} module.
        address paymentProcessor = IModuleFactory_v1(moduleFactory).createModule(
            paymentProcessorConfig.metadata,
            IOrchestrator_v1(clone),
            paymentProcessorConfig.configData
        );

        // Deploy and cache optional modules.
        uint modulesLen = moduleConfigs.length;
        address[] memory modules = new address[](modulesLen);
        for (uint i; i < modulesLen; ++i) {
            modules[i] = IModuleFactory_v1(moduleFactory).createModule(
                moduleConfigs[i].metadata,
                IOrchestrator_v1(clone),
                moduleConfigs[i].configData
            );
        }

        if (orchestratorConfig.owner == address(0)) {
            revert OrchestratorFactory_v1__OrchestratorOwnerIsInvalid();
        }

        emit OrchestratorCreated(_orchestratorIdCounter, clone);

        // Initialize orchestrator.
        IOrchestrator_v1(clone).init(
            _orchestratorIdCounter,
            modules,
            IFundingManager_v1(fundingManager),
            IAuthorizer_v1(authorizer),
            IPaymentProcessor_v1(paymentProcessor)
        );

        // Second round of module initializations to satisfy cross-referencing between modules
        // This can be run post the orchestrator initialization. This ensures a few more variables are
        // available that are set during the orchestrator init function.
        for (uint i; i < modulesLen; ++i) {
            if (_dependencyInjectionRequired(moduleConfigs[i].dependencyData)) {
                IModule_v1(modules[i]).init2(
                    IOrchestrator_v1(clone), moduleConfigs[i].dependencyData
                );
            }
        }

        // Also, running the init2 functionality on the compulsory modules excluded from the modules array
        if (_dependencyInjectionRequired(fundingManagerConfig.dependencyData)) {
            IModule_v1(fundingManager).init2(
                IOrchestrator_v1(clone), fundingManagerConfig.dependencyData
            );
        }
        if (_dependencyInjectionRequired(authorizerConfig.dependencyData)) {
            IModule_v1(authorizer).init2(
                IOrchestrator_v1(clone), authorizerConfig.dependencyData
            );
        }
        if (_dependencyInjectionRequired(paymentProcessorConfig.dependencyData))
        {
            IModule_v1(paymentProcessor).init2(
                IOrchestrator_v1(clone), paymentProcessorConfig.dependencyData
            );
        }

        return IOrchestrator_v1(clone);
    }

    /// @inheritdoc IOrchestratorFactory_v1
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
        (requirement,) = abi.decode(data, (bool, string[]));
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
