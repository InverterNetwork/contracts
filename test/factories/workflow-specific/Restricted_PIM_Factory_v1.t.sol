// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Internal Dependencies
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IRestricted_PIM_Factory_v1} from
    "src/factories/interfaces/IRestricted_PIM_Factory_v1.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {Restricted_PIM_Factory_v1} from
    "src/factories/workflow-specific/Restricted_PIM_Factory_v1.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract Restricted_PIM_Factory_v1Test is E2ETest {
    // SuT
    Restricted_PIM_Factory_v1 factory;

    // Deployment Parameters
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveBase_v1.IssuanceToken issuanceTokenParams;

    address workflowAdmin = vm.addr(420);

    address factoryDeployer = vm.addr(1);
    address workflowDeployer = vm.addr(2);
    address mockTrustedForwarder = vm.addr(3);
    address alice = vm.addr(0xA11CE);

    uint initialIssuuanceSupply = 122_727_272_727_272_727_272_727;
    uint initialCollateralSupply = 3_163_408_614_166_851_161;
    uint firstCollateralIn = 100_000_000;
    uint32 reserveRatio = 160_000;

    function setUp() public override {
        super.setUp();

        // deploy new factory
        factory = new Restricted_PIM_Factory_v1(
            address(orchestratorFactory), factoryDeployer, mockTrustedForwarder
        );
        assert(factory.owner() == factoryDeployer);

        // Orchestrator/Workflow config
        workflowConfig = IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Authorizer
        setUpRoleAuthorizer();
        authorizerConfig = IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(address(workflowAdmin))
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        paymentProcessorConfig = IOrchestratorFactory_v1.ModuleConfig(
            simplePaymentProcessorMetadata, bytes("")
        );

        // Additional Logic Modules: bounty manager
        setUpBountyManager();
        logicModuleConfigs.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bountyManagerMetadata, bytes("")
            )
        );

        // Funding Manager: Bancor Virtual Supply
        setUpBancorVirtualSupplyBondingCurveFundingManager();
        bcProperties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
            .BondingCurveProperties({
            formula: address(formula),
            reserveRatioForBuying: reserveRatio,
            reserveRatioForSelling: reserveRatio,
            buyFee: 0,
            sellFee: 0,
            buyIsOpen: true,
            sellIsOpen: true,
            initialIssuanceSupply: initialIssuuanceSupply,
            initialCollateralSupply: initialCollateralSupply
        });

        fundingManagerConfig = IOrchestratorFactory_v1.ModuleConfig(
            restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata, // TODO: test with restricted version of bonding curve
            abi.encode(address(0), bcProperties, token)
        );

        // Put issuance token params in storage
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        // mint collateral token to deployer and approve to factory
        token.mint(address(this), type(uint).max);
        token.approve(address(factory), type(uint).max);

        console.log("address(this): ", address(this));
    }

    /* Test testCreatePIMWorkflow
        ├── given the default config
        │   └── when called
        │       └── then it deploys, cleans up minting rights and makes first purchase
        └── given withInitialLiquidity flag is set to true
        |   └── when called
        |   │   └── then the curve receives initial collateral supply and initial issuance supply is minted to recipient
        └── given withInitialLiquidity flag is set to false
        |   └── when called
        |   │   └── then the curve doesn't receive initial collateral supply and burns initial issuance supply
        └── given both renounce flags are set
        |   └── when called
        |       └── then the issuance token doesn't have owner and factory remains workflow admin
        └── given only isRenouncedIssuanceToken flag is set
        |   └── when called
        |       └── then issuance token doesn't have owner and admin (from params) is workflow admin
        └── given only isRenouncedWorkflow flag is set
        |   └── when called
        |       └── then admin (from params) is owner of issuance token and factory is workflow admin
        └── given msg.sender hasn't approved collateral token for factory
            └── when called
                └── then it reverts   
    */

    function testCreatePIMWorkflow_WithRestrictedBondingCurve() public {
        // CHECK: event is emitted
        vm.expectEmit(false, false, false, false);
        emit IRestricted_PIM_Factory_v1.PIMWorkflowCreated(
            address(0), address(0), address(this)
        );

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams
        );

        // CHECK: factory DOES NOT have minting rights on token anymore
        bool isFactoryStillMinter =
            issuanceToken.allowedMinters(address(factory));
        assertFalse(isFactoryStillMinter);
        // CHECK: bonding curve module HAS minting rights on token
        bool isBcMinter =
            issuanceToken.allowedMinters(address(orchestrator.fundingManager()));
        assertTrue(isBcMinter);
        // CHECK: initialAdmin HAS curve interaction role
        bytes32 curveAccess =
        IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        ).CURVE_INTERACTION_ROLE();
        console.log(
            orchestrator.authorizer().hasRole(curveAccess, workflowAdmin)
        );
        assertTrue(
            orchestrator.authorizer().hasRole(curveAccess, workflowAdmin)
        );
        // CHECK: initialAdmin IS orchestrator admin
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertTrue(orchestrator.authorizer().hasRole(adminRole, workflowAdmin));
    }
}
