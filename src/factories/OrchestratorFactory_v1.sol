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
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// Internal Dependencies
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";
import {InverterTransparentUpgradeableProxy_v1} from
    "src/proxies/InverterTransparentUpgradeableProxy_v1.sol";
import {InverterProxyAdmin_v1} from "src/proxies/InverterProxyAdmin_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    Initializable
} from "@oz-up/access/Ownable2StepUpgradeable.sol";

/**
 * @title   Inverter Orchestrator Factory
 *
 * @notice  {OrchestratorFactory_v1} facilitates the deployment of {Orchestrator_v1}s and their
 *          associated modules for the Inverter Network, ensuring seamless creation and
 *          configuration of various components in a single transaction.
 *
 * @dev     Utilizes {ERC2771ContextUpgradeable} for meta-transaction capabilities and {ERC165Upgradeable} for interface
 *          detection. {Orchestrator_v1}s are deployed through EIP-1167 minimal proxies for efficiency.
 *          Integrates with the module factory to instantiate necessary modules with custom
 *          configurations, supporting complex setup with interdependencies among modules.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract OrchestratorFactory_v1 is
    IOrchestratorFactory_v1,
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
    ERC165Upgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IOrchestratorFactory_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IOrchestratorFactory_v1
    IInverterBeacon_v1 public override beacon;

    /// @inheritdoc IOrchestratorFactory_v1
    address public override moduleFactory;

    /// @dev	Maps the `id` to the {Orchestrator_v1}s.
    mapping(uint => address) private _orchestrators;

    /// @dev	The counter of the current {Orchestrator_v1} `id`.
    /// @dev	Starts counting from 1.
    uint private _orchestratorIdCounter;

    /// @dev	Maps a users address to a nonce.
    ///         Used for the create2-based deployment.
    mapping(address => uint) private _deploymentNonces;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------------
    // Modifier

    /// @dev    Modifier to guarantee that the given id is valid.
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
    {
        _disableInitializers();
    }

    /// @notice The factories initializer function.
    /// @param  governor_ The address of the {Governor_v1} contract.
    /// @param  beacon_ The address of the {IInverterBeacon_v1} containing the {Orchestrator_v1} implementation.
    /// @param  moduleFactory_ The address of the {ModuleFactory_v1} contract.
    function init(
        address governor_,
        IInverterBeacon_v1 beacon_,
        address moduleFactory_
    ) external initializer {
        __Ownable_init(governor_);

        if (
            !ERC165Upgradeable(address(beacon_)).supportsInterface(
                type(IInverterBeacon_v1).interfaceId
            )
        ) {
            revert OrchestratorFactory__InvalidBeacon();
        }
        beacon = beacon_;
        moduleFactory = moduleFactory_;
        emit OrchestratorFactoryInitialized(address(beacon_), moduleFactory_);
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IOrchestratorFactory_v1
    function createOrchestrator(
        WorkflowConfig memory workflowConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IOrchestrator_v1) {
        address proxy;
        // If the workflow should fetch their updates themselves
        if (workflowConfig.independentUpdates) {
            // Deploy a proxy admin contract that owns the invidual proxies
            // Overwriting the independentUpdateAdmin as the ProxyAdmin will
            // be the actual admin of the proxy
            workflowConfig.independentUpdateAdmin = address(
                new InverterProxyAdmin_v1{salt: _createSalt()}(
                    workflowConfig.independentUpdateAdmin
                )
            );

            // Use an InverterTransparentUpgradeableProxy as a proxy
            proxy = address(
                new InverterTransparentUpgradeableProxy_v1{salt: _createSalt()}(
                    beacon, workflowConfig.independentUpdateAdmin, bytes("")
                )
            );
        }
        // If not then
        else {
            // Instead use the Beacon Structure Proxy
            proxy =
                address(new InverterBeaconProxy_v1{salt: _createSalt()}(beacon));
        }

        // Map orchestrator proxy
        _orchestrators[++_orchestratorIdCounter] = proxy;

        // Deploy and cache {IFundingManager_v1} module.
        address fundingManager = IModuleFactory_v1(moduleFactory)
            .createAndInitModule(
            fundingManagerConfig.metadata,
            IOrchestrator_v1(proxy),
            fundingManagerConfig.configData,
            workflowConfig
        );

        // Deploy and cache {IAuthorizer_v1} module.
        address authorizer = IModuleFactory_v1(moduleFactory)
            .createAndInitModule(
            authorizerConfig.metadata,
            IOrchestrator_v1(proxy),
            authorizerConfig.configData,
            workflowConfig
        );

        // Deploy and cache {IPaymentProcessor_v1} module.
        address paymentProcessor = IModuleFactory_v1(moduleFactory)
            .createAndInitModule(
            paymentProcessorConfig.metadata,
            IOrchestrator_v1(proxy),
            paymentProcessorConfig.configData,
            workflowConfig
        );

        // Deploy and cache optional modules.
        address[] memory modules =
            _createModuleProxies(moduleConfigs, proxy, workflowConfig);

        emit OrchestratorCreated(_orchestratorIdCounter, proxy);

        // Initialize orchestrator.
        IOrchestrator_v1(proxy).init(
            _orchestratorIdCounter,
            moduleFactory,
            modules,
            IFundingManager_v1(fundingManager),
            IAuthorizer_v1(authorizer),
            IPaymentProcessor_v1(paymentProcessor),
            IGovernor_v1(IModuleFactory_v1(moduleFactory).governor())
        );

        // Init the rest of the modules
        _initModules(modules, moduleConfigs, proxy);

        return IOrchestrator_v1(proxy);
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

    /// @inheritdoc IOrchestratorFactory_v1
    function getOrchestratorIDCounter() external view returns (uint) {
        return _orchestratorIdCounter;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev	Creates the modules based on their `moduleConfigs.
    /// @param  moduleConfigs The config data of the modules that will be created with this function call.
    /// @param  orchestratorProxy The address of the {Orchestrator_v1} Proxy that will be linked to the modules.
    /// @param  workflowConfig The workflow's config data.
    function _createModuleProxies(
        ModuleConfig[] memory moduleConfigs,
        address orchestratorProxy,
        WorkflowConfig memory workflowConfig
    ) internal returns (address[] memory) {
        // Deploy and cache optional modules.

        address[] memory modules = new address[](moduleConfigs.length);
        for (uint i; i < moduleConfigs.length; ++i) {
            modules[i] = IModuleFactory_v1(moduleFactory).createModuleProxy(
                moduleConfigs[i].metadata,
                IOrchestrator_v1(orchestratorProxy),
                workflowConfig
            );
        }
        return modules;
    }

    /// @dev	Internal function to initialize the modules.
    /// @param  modules The modules to initialize.
    /// @param  moduleConfigs The config data of the modules that will be initialized.
    /// @param  proxy The address of the {Orchestrator_v1} Proxy that will be linked to the modules.
    function _initModules(
        address[] memory modules,
        ModuleConfig[] memory moduleConfigs,
        address proxy
    ) internal {
        // Deploy and cache optional modules.

        for (uint i; i < modules.length; ++i) {
            IModule_v1(modules[i]).init(
                IOrchestrator_v1(proxy),
                moduleConfigs[i].metadata,
                moduleConfigs[i].configData
            );
        }
    }

    /// @dev	Internal function to generate salt for the create2-based deployment flow.
    ///         This salt is the hash of (msgSender, nonce), where the
    ///         nonce is an increasing number for each user.
    function _createSalt() internal returns (bytes32) {
        return keccak256(
            abi.encodePacked(_msgSender(), _deploymentNonces[_msgSender()]++)
        );
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

    /// Needs to be overridden, because they are imported via the Ownable2Step as well.
    function _msgSender()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// Needs to be overridden, because they are imported via the Ownable2Step as well.
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
