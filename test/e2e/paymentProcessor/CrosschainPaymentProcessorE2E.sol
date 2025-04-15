// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";
import {E2EModuleRegistry} from "test/e2e/E2EModuleRegistry.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {
    PP_Connext_CrossChain_v1,
    IPP_Connext_CrossChain_v1
} from "@pp/PP_Connext_CrossChain_v1.sol";
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

contract CrosschainPaymentProcessorE2E is E2ETest {
    // Collateral token constants
    string internal constant COLLATERAL_NAME = "Mock USDC";
    string internal constant COLLATERAL_SYMBOL = "M-USDC";
    uint8 internal constant COLLATERAL_DECIMALS = 18;

    // Contracts
    ERC20Mock collateralToken;
    IOrchestrator_v1 orchestrator;
    PP_Connext_CrossChain_v1 paymentProcessor;
    FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager;
    ERC20Issuance_v1 issuanceToken;

    // Module Configurations array
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Addresses
    address everClearSpoke;
    address weth;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        everClearSpoke = makeAddr("everClearSpoke");
        weth = makeAddr("weth");

        // Create collateral token
        collateralToken = new ERC20Mock(COLLATERAL_NAME, COLLATERAL_SYMBOL);

        // 1. Funding Manager
        setUpBancorVirtualSupplyBondingCurveFundingManager();

        // Setup issuance token properties
        issuanceToken = new ERC20Issuance_v1(
            "Bonding Curve Token", "BCT", 18, type(uint).max - 1, address(this)
        );

        // Setup bonding curve properties
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 333_333,
                reserveRatioForSelling: 333_333,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 10 ether,
                initialCollateralSupply: 30 ether
            });

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(issuanceToken, bc_properties, collateralToken)
            )
        );

        // 2. Role Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // 3. Payment Processor
        setUpConnextPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                connextPaymentProcessorMetadata,
                abi.encode(everClearSpoke, weth)
            )
        );
    }

    function test_e2e_CrosschainPaymentProcessor() public {
        // Initialize orchestrator and modules
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get module instances
        fundingManager = FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );
        paymentProcessor =
            PP_Connext_CrossChain_v1(address(orchestrator.paymentProcessor()));

        // Basic setup verification
        assertTrue(address(fundingManager) != address(0), "FM not initialized");
        assertTrue(
            address(paymentProcessor) != address(0), "PP not initialized"
        );
    }
}
