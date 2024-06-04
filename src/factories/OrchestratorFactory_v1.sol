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
    IPaymentProcessor_v1,
    IGovernor_v1
} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModuleFactory_v1} from "src/factories/interfaces/IModuleFactory_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

//External Dependencies
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    Initializable
} from "@oz-up/access/Ownable2StepUpgradeable.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

/**
 * @title   Orchestrator Factory
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
 * @author  Inverter Network
 */
contract OrchestratorFactory_v1 is
    IOrchestratorFactory_v1,
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
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
    // Storage

    /// @inheritdoc IOrchestratorFactory_v1
    address public override target;

    /// @inheritdoc IOrchestratorFactory_v1
    address public override moduleFactory;

    /// @dev Maps the id to the orchestrators
    mapping(uint => address) private _orchestrators;

    /// @dev The counter of the current orchestrator id.
    /// @dev Starts counting from 1.
    uint private _orchestratorIdCounter;

    // Storage gap for future upgrades
    uint[50] private __gap;

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
    // Constructor & Initializer

    constructor(address _trustedForwarder)
        ERC2771ContextUpgradeable(_trustedForwarder)
    {}

    /// @notice The factories initializer function.
    /// @param governor_ The address of the governor contract.
    /// @param target_ The address of the governor contract.
    /// @param moduleFactory_ The address of the module factory contract.
    function init(address governor_, address target_, address moduleFactory_)
        external
        initializer
    {
        __Ownable_init(governor_);
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
            revert OrchestratorFactory__OrchestratorOwnerIsInvalid();
        }

        emit OrchestratorCreated(_orchestratorIdCounter, clone);

        // Initialize orchestrator.
        IOrchestrator_v1(clone).init(
            _orchestratorIdCounter,
            modules,
            IFundingManager_v1(fundingManager),
            IAuthorizer_v1(authorizer),
            IPaymentProcessor_v1(paymentProcessor),
            IGovernor_v1(IModuleFactory_v1(moduleFactory).governor())
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

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

    /// Needs to be overriden, because they are imported via the Ownable2Step as well
    function _msgSender()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// Needs to be overriden, because they are imported via the Ownable2Step as well
    function _msgData()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (uint)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
