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
import {IBondingCurveFactory_v1} from
    "src/factories/interfaces/IBondingCurveFactory_v1.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BondingCurveFactory_v1} from "src/factories/BondingCurveFactory_v1.sol";
import {EventHelpers} from "test/utils/helpers/EventHelpers.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {Ownable} from "@oz/access/Ownable.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract BondingCurveFactoryV1Test is E2ETest {
    // SuT
    BondingCurveFactory_v1 factory;

    // Deployment Parameters
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveFactory_v1.IssuanceTokenParams issuanceTokenParams;

    address factoryDeployer = vm.addr(3);
    address workflowDeployer = vm.addr(1);
    address alice = vm.addr(2);

    uint initialCollateral = 300;

    event BcPimCreated(address indexed issuanceToken);

    function setUp() public override {
        super.setUp();

        // deploy new factory
        factory = new BondingCurveFactory_v1(
            address(orchestratorFactory), factoryDeployer
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
            roleAuthorizerMetadata, abi.encode(address(factory))
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
            reserveRatioForBuying: 333_333,
            reserveRatioForSelling: 333_333,
            buyFee: 0,
            sellFee: 0,
            buyIsOpen: true,
            sellIsOpen: true,
            initialIssuanceSupply: 1,
            initialCollateralSupply: 3
        });

        // Deploy Issuance Token
        issuanceTokenParams = IBondingCurveFactory_v1.IssuanceTokenParams({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1,
            initialAdmin: workflowDeployer
        });

        // mint collateral token to deployer and approve to factory
        token.mint(address(this), initialCollateral);
        token.approve(address(factory), initialCollateral);
    }

    function testCreateBondingCurve() public {
        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: true,
                isRenouncedWorkflow: true
            })
        );

        // CHECK: issuance token IS DEPLOYED and initial issuance supply IS MINTED to recipient
        assertEq(
            issuanceToken.balanceOf(alice), bcProperties.initialIssuanceSupply
        );
        // CHECK: initial collateral supply IS sent to bonding curve
        assertEq(
            token.balanceOf(address(orchestrator.fundingManager())), bcProperties.initialCollateralSupply
        );
        // CHECK: factory DOES NOT have minting rights on token anymore
        bool isFactoryStillMinter =
            issuanceToken.allowedMinters(address(factory));
        assertFalse(isFactoryStillMinter);
        // CHECK: bonding curve module HAS minting rights on token
        bool isBcMinter =
            issuanceToken.allowedMinters(address(orchestrator.fundingManager()));
        assertTrue(isBcMinter);
        // CHECK: the factory DOES NOT have admin rights over workflow anymore
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isFactoryStillAdmin =
            orchestrator.authorizer().hasRole(adminRole, address(factory));
        assertFalse(isFactoryStillAdmin);
    }

    function testCreateBondingCurve_IfFullyRenounced() public {
        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: true,
                isRenouncedWorkflow: true
            })
        );

        // CHECK: the token DOES NOT have an owner anymore
        address owner = issuanceToken.owner();
        assertEq(owner, address(0));
        // CHECK: the deployer DOES NOT get admin rights over workflow
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isDeployerAdmin = orchestrator.authorizer().hasRole(
            adminRole, address(workflowDeployer)
        );
        assertFalse(isDeployerAdmin);
    }

    function testCreateBondingCurve_IfNotRenounced() public {
        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: false,
                isRenouncedWorkflow: false
            })
        );

        // CHECK: the deployer IS owner of the token
        assertEq(issuanceToken.owner(), workflowDeployer);
        // CHECK: the deployer IS admin of the workflow
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isDeployerAdmin = orchestrator.authorizer().hasRole(
            adminRole, address(workflowDeployer)
        );
        assertTrue(isDeployerAdmin);
    }

    function testCreateBondingCurve_IfTokenRenounced() public {
        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: true,
                isRenouncedWorkflow: false
            })
        );

        // CHECK: the token DOES NOT have an owner anymore
        assertEq(issuanceToken.owner(), address(0));
        // CHECK: the deployer IS admin of the workflow
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isDeployerAdmin = orchestrator.authorizer().hasRole(
            adminRole, address(workflowDeployer)
        );
        assertTrue(isDeployerAdmin);
    }

    function testCreateBondingCurve_IfWorkflowRenounced() public {
        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: false,
                isRenouncedWorkflow: true
            })
        );

        // CHECK: the deployer IS owner of the token
        assertEq(issuanceToken.owner(), workflowDeployer);
        // CHECK: the deployer DOES NOT have admin rights over workflow
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isDeployerAdmin = orchestrator.authorizer().hasRole(
            adminRole, address(workflowDeployer)
        );
        assertFalse(isDeployerAdmin);
    }

    function testCreateBondingCurve_WithFee() public {
        // set fee on factory
        uint feeInBasisPoints = 100;
        vm.prank(factoryDeployer);
        factory.setFees(feeInBasisPoints);

        // make sure that deployer has enough collateral to pay fee and approve
        uint expectedFeeAmount = initialCollateral * feeInBasisPoints / 10000;
        token.mint(address(factory), expectedFeeAmount);
        token.approve(address(factory), initialCollateral + expectedFeeAmount);

        // create bonding curve
        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: false,
                isRenouncedWorkflow: false
            })
        );

        // CHECK: bonding curve HAS received initial collateral supply
        address bc = address(orchestrator.fundingManager());
        assertEq(
            token.balanceOf(bc), bcProperties.initialCollateralSupply
        );
        // CHECK: factory HAS received fee
        assertEq(
            token.balanceOf(address(factory)), expectedFeeAmount
        );
    }

    function testCreateBondingCurve_FailsWithoutCollateralTokenApproval()
        public
    {
        address deployer = address(0xB0B);
        vm.prank(deployer);

        vm.expectRevert();

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: true,
                isRenouncedWorkflow: true
            })
        );
    }

    function testCreateBondingCurve_Renounced_FailsWhenFactoryNotAdmin()
        public
    {
        IOrchestratorFactory_v1.ModuleConfig memory badAuthorizerConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata, abi.encode(address(0x420))
        );

        vm.expectRevert();

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createBondingCurve(
            workflowConfig,
            badAuthorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            IBondingCurveFactory_v1.LaunchConfig({
                metadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                bcProperties: bcProperties,
                issuanceTokenParams: issuanceTokenParams,
                collateralToken: address(token),
                recipient: alice,
                isRenouncedIssuanceToken: true,
                isRenouncedWorkflow: true
            })
        );
    }
}
