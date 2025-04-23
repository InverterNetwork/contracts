// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {ERC20IssuanceUpgradeable_Blacklist_v1} from
    "@ex/token/ERC20IssuanceUpgradeable_Blacklist_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {AUT_Roles_v1} from "src/modules/authorizer/role/AUT_Roles_v1.sol";
import {PP_Queue_ManualExecution_v1} from "@pp/PP_Queue_ManualExecution_v1.sol";
import {FM_PC_Oracle_Redeeming_v1} from
    "@fm/oracle/FM_PC_Oracle_Redeeming_v1.sol";
import {LM_Oracle_Permissioned_v1} from "@lm/LM_Oracle_Permissioned_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {DeploymentScript} from "script/deploymentScript/DeploymentScript.s.sol";

// External
import "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from
    "@oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract DeployAndSetupYieldBearingStableWorkflow is DeploymentScript {
    // Issuance Token
    ERC20IssuanceUpgradeable_Blacklist_v1 internal _issuanceToken;
    string internal _tokenName;
    string internal _tokenSymbol;
    uint internal _maxSupply;
    uint8 internal _tokenDecimals;
    address internal _tokenOwner;
    address internal _tokenProxyAdmin;
    address internal _blacklistManager;

    // Role Authorizer
    address internal _workflowAdmin;

    // Collateral Token (external)
    address internal _collateralToken;

    // Oracle Based Funding Manager
    address internal _projectTreasury;
    uint internal _buyFeeInBps;
    uint internal _maxBuyFeeInBps;
    uint internal _sellFeeInBps;
    uint internal _maxSellFeeInBps;
    bool internal _isDirectOperationOnly;
    bytes internal _workflowConfigData;
    address internal _whitelistRole;
    address internal _whitelistRoleAdmin;
    address internal _queueExecutorRole;
    address internal _queueExecutorRoleAdmin;

    // Manual Queue Payment Processor
    address internal _cancelledOrdersTreasury;
    address internal _failedOrdersTreasury;
    address internal _queueOperatorRole;
    address internal _queueOperatorRoleAdmin;

    // Oracle
    address internal _priceSetterRole;
    address internal _priceSetterRoleAdmin;

    // Workflow config
    bool internal _independentUpdateBool;
    address internal _independentUpdateAdmin;

    // Orchestrator
    IOrchestrator_v1 internal _orchestrator;

    // Workflow Modules
    FM_PC_Oracle_Redeeming_v1 internal _fundingManager;
    AUT_Roles_v1 internal _authorizer;
    PP_Queue_ManualExecution_v1 internal _paymentProcessor;
    LM_Oracle_Permissioned_v1 internal _oracleModule;

    function run() public override {
        console2.log("\n===============================================");
        console2.log("  DEPLOYING YIELD BEARING STABLE WORKFLOW");
        console2.log("  =======================================\n");

        // Load and validate deployment variables
        _loadAndValidateDeploymentVariables();

        // Deploy external issuance token
        _deployToken();

        // Deploy workflow
        _deployWorkflow();

        // Setup workflow
        _setupWorkflow();

        // Set workflow admin
        _setupWorkflowAdmin();

        console2.log("================================================");
        console2.log("                DEPLOYMENT SUMMARY               ");
        console2.log("================================================");
        console2.log("                Status: SUCCESSFUL               ");
        console2.log("             Chain ID: ", block.chainid);
        console2.log("      All contracts deployed and configured      ");
        console2.log("================================================\n");
    }

    // -------------------------------------------------------------------------
    // Deployment functions

    function _deployToken() internal {
        console2.log("Token Deployment");
        console2.log("----------------");
        console2.log("  Deploying issuance token...");

        // Deploy the implementation contract
        vm.startBroadcast(deployerPrivateKey);
        ERC20IssuanceUpgradeable_Blacklist_v1 implementation =
            new ERC20IssuanceUpgradeable_Blacklist_v1();
        // Deploy a simple proxy that delegates to the implementation
        address proxy = address(
            new TransparentUpgradeableProxy(
                address(implementation),
                _tokenProxyAdmin,
                abi.encodeWithSelector(
                    ERC20IssuanceUpgradeable_Blacklist_v1
                        .__ERC20IssuanceBlacklist_init
                        .selector,
                    _tokenName,
                    _tokenSymbol,
                    _tokenDecimals,
                    _maxSupply
                )
            )
        );
        vm.stopBroadcast();

        // Store issuance token
        _issuanceToken = ERC20IssuanceUpgradeable_Blacklist_v1(proxy);
        console2.log("  [OK] Issuance token deployed successfully");
        _logAddress("  Issuance token deployed at", proxy);
    }

    function _deployWorkflow() internal {
        console2.log("\nWorkflow Deployment");
        console2.log("-------------------");
        // ---------------------------------------------------------------------
        // Deploy workflow

        // Get the orchestrator factory
        IOrchestratorFactory_v1 orchestratorFactory =
            IOrchestratorFactory_v1(getDeployedOrchestratorFactory());

        console2.log("  Deploying Inverter Protocol workflow...");
        // Create workflow
        vm.startBroadcast(deployerPrivateKey);
        _orchestrator = orchestratorFactory.createOrchestrator(
            _getWorkflowConfig(),
            _getFundingManagerConfig(),
            _getAuthorizerConfig(),
            _getPaymentProcessorConfig(),
            _getOptionalModulesConfigs()
        );
        vm.stopBroadcast();

        // ---------------------------------------------------------------------
        // Store workflow addresses

        // Store modules
        // Store funding manager
        _fundingManager =
            FM_PC_Oracle_Redeeming_v1(address(_orchestrator.fundingManager()));
        // Store Authorizer
        _authorizer = AUT_Roles_v1(address(_orchestrator.authorizer()));
        // Store Payment Processor
        _paymentProcessor = PP_Queue_ManualExecution_v1(
            address(_orchestrator.paymentProcessor())
        );
        // Store Oracle module
        _oracleModule =
            LM_Oracle_Permissioned_v1(address(_orchestrator.listModules()[0]));

        // ---------------------------------------------------------------------
        // Validate workflow deployment

        console2.log("  Validating deployed workflow...");
        _validateWorkflowDeployment();
        console2.log("  [OK] Workflow deployed successfully\n");

        // ---------------------------------------------------------------------
        // Log workflow addresses
        console2.log("Deployed Contract Addresses");
        console2.log("---------------------------");
        _logAddress("  * Orchestrator", address(_orchestrator));
        _logAddress("  * Funding Manager", address(_fundingManager));
        _logAddress("  * Authorizer", address(_authorizer));
        _logAddress("  * Payment Processor", address(_paymentProcessor));
        _logAddress("  * Oracle Module", address(_oracleModule));
        _logAddress("  * Issuance Token", address(_issuanceToken));
        console2.log("\n");
    }

    // -------------------------------------------------------------------------
    // Setup functions

    function _setupWorkflowAdmin() internal {
        console2.log("Administrative Setup");
        console2.log("--------------------");

        console2.log("Setting up workflow admin...");
        vm.startBroadcast(deployerPrivateKey);
        _authorizer.grantRole(_authorizer.getAdminRole(), _workflowAdmin);
        require(
            _authorizer.checkForRole(_authorizer.getAdminRole(), _workflowAdmin)
                == true,
            "Workflow admin not set correctly"
        );
        console2.log("  [OK] Workflow admin configured");
        console2.log("  Workflow admin: ", _workflowAdmin);

        // Revoke admin role from deployer
        console2.log("\n  Revoking admin role from deployer...");
        _authorizer.revokeRole(_authorizer.getAdminRole(), deployer);
        require(
            _authorizer.checkForRole(_authorizer.getAdminRole(), deployer)
                == false,
            "Admin role not revoked from deployer"
        );
        vm.stopBroadcast();
        console2.log("  [OK] Admin role revoked from deployer\n");
    }

    function _setupWorkflow() internal {
        console2.log("Workflow Configuration");
        console2.log("----------------------");
        // Setup token
        _setupAndVerifyToken();
        // Setup Oracle
        _setupAndVerifyOracle();
        // Setup Funding Manager
        _setupAndVerifyFundingManager();
        // Setup Payment Processor
        _setupAndVerifyPaymentProcessor();
        console2.log("\n  [OK] Workflow setup successful\n");
    }

    function _setupAndVerifyPaymentProcessor() internal {
        console2.log("\n  Payment Processor Setup");
        // ---------------------------------------------------------------------
        // Roles
        vm.startBroadcast(deployerPrivateKey);
        // Set Queue Operator Role
        _paymentProcessor.grantModuleRole(
            _paymentProcessor.getQueueOperatorRole(), _queueOperatorRole
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_paymentProcessor),
                    _paymentProcessor.getQueueOperatorRole()
                ),
                _queueOperatorRole
            ),
            "Queue operator role not set correctly"
        );
        _logAddress("    * Queue Operator", _queueOperatorRole);

        // Set Queue Operator Role Admin
        _paymentProcessor.grantModuleRole(
            _paymentProcessor.getQueueOperatorRoleAdmin(),
            _queueOperatorRoleAdmin
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_paymentProcessor),
                    _paymentProcessor.getQueueOperatorRoleAdmin()
                ),
                _queueOperatorRoleAdmin
            ),
            "Queue operator role admin not set correctly"
        );
        _logAddress("    * Queue Op Admin", _queueOperatorRoleAdmin);

        // Set admin role for queue operator role
        _authorizer.transferAdminRole(
            _authorizer.generateRoleId(
                address(_paymentProcessor),
                _paymentProcessor.getQueueOperatorRole()
            ),
            _authorizer.generateRoleId(
                address(_paymentProcessor),
                _paymentProcessor.getQueueOperatorRoleAdmin()
            )
        );
        require(
            _authorizer.getRoleAdmin(
                _authorizer.generateRoleId(
                    address(_paymentProcessor),
                    _paymentProcessor.getQueueOperatorRole()
                )
            )
                == _authorizer.generateRoleId(
                    address(_paymentProcessor),
                    _paymentProcessor.getQueueOperatorRoleAdmin()
                ),
            "Admin role for queue operator role not set correctly"
        );
        vm.stopBroadcast();
    }

    function _setupAndVerifyFundingManager() internal {
        console2.log("\n  Funding Manager Setup");
        // ---------------------------------------------------------------------
        // Setters
        vm.startBroadcast(deployerPrivateKey);
        // Set Oracle address
        _fundingManager.setOracleAddress(address(_oracleModule));
        require(
            _fundingManager.getOracle() == address(_oracleModule),
            "Funding manager oracle not set correctly"
        );
        _logAddress("    * Oracle", address(_oracleModule));
        // ---------------------------------------------------------------------
        // Roles

        // Set Whitelist Role
        _fundingManager.grantModuleRole(
            _fundingManager.getWhitelistRole(), _whitelistRole
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_fundingManager), _fundingManager.getWhitelistRole()
                ),
                _whitelistRole
            ),
            "Whitelist role not set correctly"
        );
        _logAddress("    * Whitelist Role", _whitelistRole);

        // Set Whitelist Role Admin
        _fundingManager.grantModuleRole(
            _fundingManager.getWhitelistRoleAdmin(), _whitelistRoleAdmin
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_fundingManager),
                    _fundingManager.getWhitelistRoleAdmin()
                ),
                _whitelistRoleAdmin
            ),
            "Whitelist role admin not set correctly"
        );
        _logAddress("    * Whitelist Admin", _whitelistRoleAdmin);

        // Set admin role for whitelist role
        _authorizer.transferAdminRole(
            _authorizer.generateRoleId(
                address(_fundingManager), _fundingManager.getWhitelistRole()
            ),
            _authorizer.generateRoleId(
                address(_fundingManager),
                _fundingManager.getWhitelistRoleAdmin()
            )
        );
        require(
            _authorizer.getRoleAdmin(
                _authorizer.generateRoleId(
                    address(_fundingManager), _fundingManager.getWhitelistRole()
                )
            )
                == _authorizer.generateRoleId(
                    address(_fundingManager),
                    _fundingManager.getWhitelistRoleAdmin()
                ),
            "Admin role for whitelist role not set correctly"
        );

        // Set Queue Executor Role
        _fundingManager.grantModuleRole(
            _fundingManager.getQueueExecutorRole(), _queueExecutorRole
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_fundingManager),
                    _fundingManager.getQueueExecutorRole()
                ),
                _queueExecutorRole
            ),
            "Queue executor role not set correctly"
        );
        _logAddress("    * Queue Executor", _queueExecutorRole);

        // Set Queue Executor Role Admin
        _fundingManager.grantModuleRole(
            _fundingManager.getQueueExecutorRoleAdmin(), _queueExecutorRoleAdmin
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_fundingManager),
                    _fundingManager.getQueueExecutorRoleAdmin()
                ),
                _queueExecutorRoleAdmin
            ),
            "Queue executor role admin not set correctly"
        );
        _logAddress("    * Queue Exec Admin", _queueExecutorRoleAdmin);

        // Set admin role for queue executor role
        _authorizer.transferAdminRole(
            _authorizer.generateRoleId(
                address(_fundingManager), _fundingManager.getQueueExecutorRole()
            ),
            _authorizer.generateRoleId(
                address(_fundingManager),
                _fundingManager.getQueueExecutorRoleAdmin()
            )
        );
        require(
            _authorizer.getRoleAdmin(
                _authorizer.generateRoleId(
                    address(_fundingManager),
                    _fundingManager.getQueueExecutorRole()
                )
            )
                == _authorizer.generateRoleId(
                    address(_fundingManager),
                    _fundingManager.getQueueExecutorRoleAdmin()
                ),
            "Admin role for queue executor role not set correctly"
        );
        vm.stopBroadcast();
    }

    function _setupAndVerifyOracle() internal {
        console2.log("\n  Oracle Setup");
        // ---------------------------------------------------------------------
        // Roles

        vm.startBroadcast(deployerPrivateKey);
        // Set price setter role
        _oracleModule.grantModuleRole(
            _oracleModule.getPriceSetterRole(), _priceSetterRole
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_oracleModule), _oracleModule.getPriceSetterRole()
                ),
                _priceSetterRole
            ),
            "Price setter role not set correctly"
        );
        _logAddress("    * Price Setter", _priceSetterRole);

        // Set price setter role admin
        _oracleModule.grantModuleRole(
            _oracleModule.getPriceSetterRoleAdmin(), _priceSetterRoleAdmin
        );
        require(
            _authorizer.checkForRole(
                _authorizer.generateRoleId(
                    address(_oracleModule),
                    _oracleModule.getPriceSetterRoleAdmin()
                ),
                _priceSetterRoleAdmin
            ),
            "Price setter role admin not set correctly"
        );
        _logAddress("    * Price Setter Admin", _priceSetterRoleAdmin);

        // Set admin role for price setter role
        _authorizer.transferAdminRole(
            _authorizer.generateRoleId(
                address(_oracleModule), _oracleModule.getPriceSetterRole()
            ),
            _authorizer.generateRoleId(
                address(_oracleModule), _oracleModule.getPriceSetterRoleAdmin()
            )
        );
        require(
            _authorizer.getRoleAdmin(
                _authorizer.generateRoleId(
                    address(_oracleModule), _oracleModule.getPriceSetterRole()
                )
            )
                == _authorizer.generateRoleId(
                    address(_oracleModule), _oracleModule.getPriceSetterRoleAdmin()
                ),
            "Admin role for price setter role not set correctly"
        );
        vm.stopBroadcast();
    }

    function _setupAndVerifyToken() internal {
        console2.log("\n  Issuance Token Setup");
        // ---------------------------------------------------------------------
        // Setters

        // Set minter
        vm.startBroadcast(deployerPrivateKey);
        _issuanceToken.setMinter(address(_fundingManager), true);
        require(
            _issuanceToken.allowedMinters(address(_fundingManager)),
            "Minter not set correctly"
        );
        _logAddress("    * Minter", address(_fundingManager));
        // ---------------------------------------------------------------------
        // Roles

        // Set Blacklist Manager
        _issuanceToken.setBlacklistManager(_blacklistManager, true);
        require(
            _issuanceToken.isBlacklistManager(_blacklistManager) == true,
            "Blacklist manager not set correctly"
        );
        _logAddress("    * Blacklist Manager", _blacklistManager);
        // Set new owner
        _issuanceToken.transferOwnership(_tokenOwner);
        require(
            _issuanceToken.owner() == _tokenOwner,
            "Token owner not set correctly"
        );
        _logAddress("    * Owner", _tokenOwner);
        vm.stopBroadcast();
    }

    // -------------------------------------------------------------------------
    // Workflow config functions

    function _getWorkflowConfig()
        internal
        view
        returns (IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig_)
    {
        workflowConfig_ = IOrchestratorFactory_v1.WorkflowConfig(
            _independentUpdateBool, _independentUpdateAdmin
        );
    }

    function _getFundingManagerConfig()
        internal
        view
        returns (
            IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig_
        )
    {
        // Get the funding manager config
        fundingManagerConfig_ = IOrchestratorFactory_v1.ModuleConfig(
            IModule_v1.Metadata(
                1,
                0,
                0,
                "https://github.com/InverterNetwork/contracts",
                "FM_PC_Oracle_Redeeming_v1"
            ),
            abi.encode(
                _projectTreasury,
                _issuanceToken,
                _collateralToken,
                _buyFeeInBps,
                _sellFeeInBps,
                _maxSellFeeInBps,
                _maxBuyFeeInBps,
                _isDirectOperationOnly
            )
        );
    }

    function _getAuthorizerConfig()
        internal
        view
        returns (IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig_)
    {
        // Get the authorizer config
        authorizerConfig_ = IOrchestratorFactory_v1.ModuleConfig(
            IModule_v1.Metadata(
                1,
                0,
                0,
                "https://github.com/InverterNetwork/contracts",
                "AUT_Roles_v1"
            ),
            abi.encode(deployer) // Set deployer as initial admin. Later replaced by the workflow admin.
        );
    }

    function _getPaymentProcessorConfig()
        internal
        view
        returns (
            IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig_
        )
    {
        paymentProcessorConfig_ = IOrchestratorFactory_v1.ModuleConfig(
            IModule_v1.Metadata(
                1,
                0,
                0,
                "https://github.com/InverterNetwork/contracts",
                "PP_Queue_ManualExecution_v1"
            ),
            abi.encode(_cancelledOrdersTreasury, _failedOrdersTreasury)
        );
    }

    function _getOptionalModulesConfigs()
        internal
        view
        returns (
            IOrchestratorFactory_v1.ModuleConfig[] memory optionalModulesConfigs_
        )
    {
        optionalModulesConfigs_ = new IOrchestratorFactory_v1.ModuleConfig[](1);
        optionalModulesConfigs_[0] = IOrchestratorFactory_v1.ModuleConfig(
            IModule_v1.Metadata(
                1,
                0,
                0,
                "https://github.com/InverterNetwork/contracts",
                "LM_Oracle_Permissioned_v1"
            ),
            abi.encode(_collateralToken)
        );
    }

    // -------------------------------------------------------------------------
    // Validation functions

    function _loadAndValidateDeploymentVariables() internal {
        console2.log("Environment Setup");
        console2.log("-----------------");
        console2.log("  Loading and validating environment variables...");

        // Load and validate environment variables of workflow
        _loadAndValidateEnvironmentVariablesOfWorkflow();

        // Validate Inverter Protocol deployment variables from ENV
        _validateInverterProtocolDeploymentVariables();

        // Load Inverter Protocol deployed contracts
        loadDeployedContracts();
        console2.log(
            "  [OK] Loading Inverter Protocol Infrastructure Contracts\n"
        );
    }

    function _validateWorkflowDeployment() internal view {
        // Validate deployments
        _validateFundingManagerDeployment();
        _validateAuthorizerDeployment();
        _validatePaymentProcessorDeployment();
        _validateOracleDeployment();
        console2.log("  [OK] Deployed workflow validated");
    }

    function _validateOracleDeployment() internal view {
        // Validate oracle deployment
        require(
            _oracleModule.getCollateralTokenDecimals()
                == IERC20Metadata(_collateralToken).decimals(),
            "Oracle collateral token decimals not set correctly"
        );
        require(
            _oracleModule.orchestrator() == _orchestrator,
            "Oracle orchestrator not set correctly"
        );
    }

    function _validatePaymentProcessorDeployment() internal view {
        // Validate payment processor deployment
        require(
            _paymentProcessor.getCanceledOrdersTreasury()
                == _cancelledOrdersTreasury,
            "Payment processor cancelled orders treasury not set"
        );
        require(
            _paymentProcessor.getFailedOrdersTreasury() == _failedOrdersTreasury,
            "Payment processor failed orders treasury not set"
        );
        require(
            _paymentProcessor.orchestrator() == _orchestrator,
            "Payment processor orchestrator not set correctly"
        );
    }

    function _validateAuthorizerDeployment() internal view {
        // Validate authorizer deployment
        require(
            _authorizer.checkForRole(_authorizer.getAdminRole(), deployer),
            "Authorizer admin role not set correctly"
        );
        require(
            _authorizer.orchestrator() == _orchestrator,
            "Authorizer orchestrator not set correctly"
        );
    }

    function _validateFundingManagerDeployment() internal view {
        // Validate funding manager deployment
        require(
            _fundingManager.getProjectTreasury() == _projectTreasury,
            "Funding manager project treasury not set"
        );
        require(
            _fundingManager.getIssuanceToken() == address(_issuanceToken),
            "Funding manager issuance token not set"
        );
        require(
            _fundingManager.token() == IERC20(_collateralToken),
            "Funding manager token not set"
        );
        require(
            _fundingManager.getBuyFee() == _buyFeeInBps,
            "Funding manager buy fee not set"
        );
        require(
            _fundingManager.getSellFee() == _sellFeeInBps,
            "Funding manager sell fee not set"
        );
        require(
            _fundingManager.getMaxProjectBuyFee() == _maxBuyFeeInBps,
            "Funding manager max project buy fee not set"
        );
        require(
            _fundingManager.getMaxProjectSellFee() == _maxSellFeeInBps,
            "Funding manager max project sell fee not set"
        );
        require(
            _fundingManager.getIsDirectOperationsOnly()
                == _isDirectOperationOnly,
            "Funding manager is direct operations only not set"
        );
        require(
            _fundingManager.orchestrator() == _orchestrator,
            "Funding manager orchestrator not set correctly"
        );
    }

    function _validateInverterProtocolDeploymentVariables() internal view {
        _validateValidChainId(block.chainid);
        console2.log("  [OK] Validating Inverter Protocol deployment address");
    }

    function _validateValidChainId(uint chainId_) internal view {
        for (uint i = 0; i < deployedMainnets.length; i++) {
            if (chainId_ == deployedMainnets[i]) {
                return;
            }
        }
        for (uint i = 0; i < deployedTestnets.length; i++) {
            if (chainId_ == deployedTestnets[i]) {
                return;
            }
        }
        // revert("Invalid chain id");
    }

    function _loadAndValidateEnvironmentVariablesOfWorkflow() internal {
        // Issuance Token
        // ---------------------------------------------------------------------
        _tokenName = vm.envString("TOKEN_NAME_STRING");
        require(bytes(_tokenName).length > 0, "Token name not set");

        _tokenSymbol = vm.envString("TOKEN_SYMBOL_STRING");
        require(bytes(_tokenSymbol).length > 0, "Token symbol not set");

        _tokenDecimals = uint8(vm.envUint("TOKEN_DECIMALS"));
        require(_tokenDecimals > 0, "Token decimals not set");

        _maxSupply = vm.envUint("MAX_SUPPLY");
        require(_maxSupply > 0, "Max supply not set");

        _tokenOwner = vm.envAddress("TOKEN_OWNER_ADDRESS");
        require(_tokenOwner != address(0), "Token owner not set");

        _tokenProxyAdmin = vm.envAddress("TOKEN_PROXY_ADMIN_ADDRESS");
        require(_tokenProxyAdmin != address(0), "Token proxy admin not set");

        _blacklistManager = vm.envAddress("BLACKLIST_MANAGER_ADDRESS");
        require(_blacklistManager != address(0), "Blacklist manager not set");

        // Role Authorizer
        // ---------------------------------------------------------------------
        _workflowAdmin = vm.envAddress("WORKFLOW_ADMIN_ADDRESS");
        require(_workflowAdmin != address(0), "Workflow admin not set");

        // Collateral Token (external)
        // ---------------------------------------------------------------------
        _collateralToken = vm.envAddress("COLLATERAL_TOKEN_ADDRESS");
        require(_collateralToken != address(0), "Collateral token not set");

        // Oracle Based Funding Manager
        // ---------------------------------------------------------------------
        _projectTreasury = vm.envAddress("PROJECT_TREASURY_ADDRESS");
        require(_projectTreasury != address(0), "Project treasury not set");

        _buyFeeInBps = vm.envUint("BUY_FEE_IN_BPS");

        _maxBuyFeeInBps = vm.envUint("MAX_BUY_FEE_IN_BPS");

        _sellFeeInBps = vm.envUint("SELL_FEE_IN_BPS");

        _maxSellFeeInBps = vm.envUint("MAX_SELL_FEE_IN_BPS");

        _isDirectOperationOnly = vm.envBool("IS_DIRECT_OPERATION_ONLY_BOOL");

        _whitelistRole = vm.envAddress("WHITELIST_ROLE_ADDRESS");
        require(_whitelistRole != address(0), "Whitelist role not set");

        _whitelistRoleAdmin = vm.envAddress("WHITELIST_ROLE_ADMIN_ADDRESS");
        require(
            _whitelistRoleAdmin != address(0), "Whitelist role admin not set"
        );

        _queueExecutorRole = vm.envAddress("QUEUE_EXECUTOR_ROLE_ADDRESS");
        require(_queueExecutorRole != address(0), "Queue executor role not set");

        _queueExecutorRoleAdmin =
            vm.envAddress("QUEUE_EXECUTOR_ROLE_ADMIN_ADDRESS");
        require(
            _queueExecutorRoleAdmin != address(0),
            "Queue executor role admin not set"
        );

        // Oracle
        // ---------------------------------------------------------------------
        _priceSetterRole = vm.envAddress("PRICE_SETTER_ROLE_ADDRESS");
        require(_priceSetterRole != address(0), "Price setter role not set");

        _priceSetterRoleAdmin = vm.envAddress("PRICE_SETTER_ROLE_ADMIN_ADDRESS");
        require(
            _priceSetterRoleAdmin != address(0),
            "Price setter role admin not set"
        );

        // Manual Queue Payment Processor
        // ---------------------------------------------------------------------
        _cancelledOrdersTreasury =
            vm.envAddress("CANCELLED_ORDER_TREASURY_ADDRESS");
        require(
            _cancelledOrdersTreasury != address(0),
            "Cancelled orders treasury not set"
        );

        _failedOrdersTreasury = vm.envAddress("FAILED_ORDER_TREASURY_ADDRESS");
        require(
            _failedOrdersTreasury != address(0),
            "Failed orders treasury not set"
        );

        _queueOperatorRole = vm.envAddress("QUEUE_OPERATOR_ROLE_ADDRESS");
        require(_queueOperatorRole != address(0), "Queue operator role not set");

        _queueOperatorRoleAdmin =
            vm.envAddress("QUEUE_EXECUTOR_ROLE_ADMIN_ADDRESS");
        require(
            _queueOperatorRoleAdmin != address(0),
            "Queue operator role admin not set"
        );

        // Workflow config
        // ---------------------------------------------------------------------
        _independentUpdateBool = vm.envBool("INDEPENDENT_UPDATE_BOOL");
        _independentUpdateAdmin =
            vm.envAddress("INDEPENDENT_UPDATE_ADMIN_ADDRESS");

        console2.log("  [OK] Environment variables loaded and validated");
    }

    // -------------------------------------------------------------------------
    // Logging functions

    function _logAddress(string memory label, address addr) internal view {
        console2.log(string.concat(label, ": "), addr);
    }
}
