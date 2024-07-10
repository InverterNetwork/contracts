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
import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    Initializable
} from "@oz-up/access/Ownable2StepUpgradeable.sol";

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
    IInverterBeacon_v1 public override beacon;

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
    {
        _disableInitializers();
    }

    /// @notice The factories initializer function.
    /// @param governor_ The address of the governor contract.
    /// @param beacon_ The address of the beacon containing the orchestrator implementation.
    /// @param moduleFactory_ The address of the module factory contract.
    function init(
        address governor_,
        IInverterBeacon_v1 beacon_,
        address moduleFactory_
    ) external initializer {
        __Ownable_init(governor_);

        if (
            !ERC165(address(beacon_)).supportsInterface(
                type(IInverterBeacon_v1).interfaceId
            )
        ) {
            revert OrchestratorFactory__InvalidBeacon();
        }

        beacon = beacon_;
        moduleFactory = moduleFactory_;
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
                new InverterProxyAdmin_v1(workflowConfig.independentUpdateAdmin)
            );

            // Use an InverterTransparentUpgradeableProxy as a proxy
            proxy = address(
                new InverterTransparentUpgradeableProxy_v1(
                    beacon, workflowConfig.independentUpdateAdmin, bytes("")
                )
            );
        }
        // If not then
        else {
            // Instead use the Beacon Structure Proxy
            proxy = address(new InverterBeaconProxy_v1(beacon));
        }

        // Map orchestrator proxy
        _orchestrators[++_orchestratorIdCounter] = proxy;

        // Deploy and cache {IFundingManager_v1} module.
        address fundingManager = IModuleFactory_v1(moduleFactory).createModule(
            fundingManagerConfig.metadata,
            IOrchestrator_v1(proxy),
            fundingManagerConfig.configData,
            workflowConfig
        );

        // Deploy and cache {IAuthorizer_v1} module.
        address authorizer = IModuleFactory_v1(moduleFactory).createModule(
            authorizerConfig.metadata,
            IOrchestrator_v1(proxy),
            authorizerConfig.configData,
            workflowConfig
        );

        // Deploy and cache {IPaymentProcessor_v1} module.
        address paymentProcessor = IModuleFactory_v1(moduleFactory).createModule(
            paymentProcessorConfig.metadata,
            IOrchestrator_v1(proxy),
            paymentProcessorConfig.configData,
            workflowConfig
        );

        // Deploy and cache optional modules.
        address[] memory modules =
            createModules(moduleConfigs, proxy, workflowConfig);

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

    function getOrchestratorIDCounter() external view returns (uint) {
        return _orchestratorIdCounter;
    }

    function createModules(
        ModuleConfig[] memory moduleConfigs,
        address proxy,
        WorkflowConfig memory workflowConfig
    ) internal returns (address[] memory) {
        // Deploy and cache optional modules.

        address[] memory modules = new address[](moduleConfigs.length);
        for (uint i; i < moduleConfigs.length; ++i) {
            modules[i] = IModuleFactory_v1(moduleFactory).createModule(
                moduleConfigs[i].metadata,
                IOrchestrator_v1(proxy),
                moduleConfigs[i].configData,
                workflowConfig
            );
        }
        return modules;
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
