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
import {IPIM_WorkflowFactory_v1} from
    "src/factories/interfaces/IPIM_WorkflowFactory_v1.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {PIM_WorkflowFactory_v1} from
    "src/factories/workflow-specific/PIM_WorkflowFactory_v1.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract PIM_WorkflowFactory_v1Test is E2ETest {
    // SuT
    PIM_WorkflowFactory_v1 factory;

    // Deployment Parameters
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IPIM_WorkflowFactory_v1.IssuanceTokenParams issuanceTokenParams;

    address factoryDeployer = vm.addr(1);
    address workflowDeployer = vm.addr(2);
    address mockTrustedForwarder = vm.addr(3);
    address alice = vm.addr(0xA11CE);

    uint initialCollateral = 3;

    event PIMWorkflowCreated(address indexed issuanceToken);

    function setUp() public override {
        super.setUp();

        // deploy new factory
        factory = new PIM_WorkflowFactory_v1(
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
        issuanceTokenParams = IPIM_WorkflowFactory_v1.IssuanceTokenParams({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        // mint collateral token to deployer and approve to factory
        token.mint(address(this), initialCollateral);
        token.approve(address(factory), initialCollateral);
    }

    function testCreatePIMWorkflow() public {
        // CHECK: event is emitted
        vm.expectEmit(false, false, false, false);
        emit IPIM_WorkflowFactory_v1.PIMWorkflowCreated(
            address(0), address(0), address(0), address(0), true, true
        );
        // get default config
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        // CHECK: factory DOES NOT have minting rights on token anymore
        bool isFactoryStillMinter =
            issuanceToken.allowedMinters(address(factory));
        assertFalse(isFactoryStillMinter);
        // CHECK: bonding curve module HAS minting rights on token
        bool isBcMinter =
            issuanceToken.allowedMinters(address(orchestrator.fundingManager()));
        assertTrue(isBcMinter);
    }

    function testCreatePIMWorkflow_WithInitialLiquidity() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();
        pimConfig.withInitialLiquidity = true; // just to highlight what is being tested

        uint preCollateralBalance = token.balanceOf(address(this));

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        uint postCollateralBalance = token.balanceOf(address(this));
        // CHECK: curve HAS received initial collateral supply
        assertTrue(
            preCollateralBalance - postCollateralBalance == initialCollateral
        );
        // CHECK: initialIssuanceSupply is SENT to recipient
        assertEq(
            issuanceToken.balanceOf(pimConfig.recipient),
            bcProperties.initialIssuanceSupply
        );
    }

    function testCreatePIMWorkflow_WithoutInitialLiquidity() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();
        pimConfig.withInitialLiquidity = false;

        uint preCollateralBalance = token.balanceOf(address(this));

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        uint postCollateralBalance = token.balanceOf(address(this));

        // CHECK: deployer has still SAME balance of collateral token as before (= nothing sent to curve)
        assertEq(preCollateralBalance, postCollateralBalance);
        // CHECK: initialIssuanceSupply is BURNT (sent to 0xDEAD)
        assertEq(
            issuanceToken.balanceOf(address(0xDEAD)),
            bcProperties.initialIssuanceSupply
        );
    }

    function testCreatePIMWorkflow_IfFullyRenounced() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();
        pimConfig.isRenouncedIssuanceToken = true;
        pimConfig.isRenouncedWorkflow = true;

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
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
        // CHECK: the factory HAS admin rights over workflow
        bool isFactoryAdmin =
            orchestrator.authorizer().hasRole(adminRole, address(factory));
        assertTrue(isFactoryAdmin);
    }

    function testCreatePIMWorkflow_IfNotRenounced() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();
        pimConfig.isRenouncedIssuanceToken = false;
        pimConfig.isRenouncedWorkflow = false;
        pimConfig.recipient = alice;
        pimConfig.admin = workflowDeployer;

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
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

    function testCreatePIMWorkflow_IfTokenRenounced() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();
        pimConfig.isRenouncedIssuanceToken = true;
        pimConfig.isRenouncedWorkflow = false;
        pimConfig.recipient = alice;
        pimConfig.admin = workflowDeployer;

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
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

    function testCreatePIMWorkflow_IfWorkflowRenounced() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();
        pimConfig.isRenouncedIssuanceToken = false;
        pimConfig.isRenouncedWorkflow = true;

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        // CHECK: the deployer IS owner of the token
        // assertEq(issuanceToken.owner(), workflowDeployer);
        // CHECK: the deployer DOES NOT have admin rights over workflow
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isDeployerAdmin = orchestrator.authorizer().hasRole(
            adminRole, address(workflowDeployer)
        );
        assertFalse(isDeployerAdmin);
        // CHECK: the factory DOES have admin rights over workflow
        bool isFactoryAdmin =
            orchestrator.authorizer().hasRole(adminRole, address(factory));
        assertTrue(isFactoryAdmin);
    }

    function testCreatePIMWorkflow_WithFee() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();

        // set fee on factory
        uint feeInBasisPoints = 100;
        vm.prank(factoryDeployer);
        factory.setCreationFee(feeInBasisPoints);

        // make sure that deployer has enough collateral to pay fee and approve
        uint expectedFeeAmount = initialCollateral * feeInBasisPoints / 10_000;
        token.mint(address(factory), expectedFeeAmount);
        token.approve(address(factory), initialCollateral + expectedFeeAmount);

        // create bonding curve
        (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        // CHECK: bonding curve HAS received initial collateral supply
        address bc = address(orchestrator.fundingManager());
        assertEq(token.balanceOf(bc), bcProperties.initialCollateralSupply);
        // CHECK: factory HAS received fee
        assertEq(token.balanceOf(address(factory)), expectedFeeAmount);
    }

    function testCreatePIMWorkflow_FailsWithoutCollateralTokenApproval()
        public
    {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();
        address deployer = address(0xB0B);
        vm.prank(deployer);

        vm.expectRevert();

        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );
    }

    function testSetCreationFee() public {
        vm.prank(factoryDeployer);
        // CHECK: event is emitted
        vm.expectEmit(true, true, true, true);
        emit IPIM_WorkflowFactory_v1.CreationFeeSet(100);
        // CHEK: fee is set
        factory.setCreationFee(100);
        assertEq(factory.creationFee(), 100);
    }

    function testSetCreationFee_FailsIfCallerIsNotOwner() public {
        vm.prank(alice);
        // CHECK: tx reverts
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector, alice
            )
        );
        factory.setCreationFee(100);
    }

    function testWithdrawCreationFee() public {
        // send tokens to factory
        token.mint(address(factory), 100);

        vm.prank(factoryDeployer);
        factory.withdrawCreationFee(token, alice);
        // CHECK: tokens are sent to alice
        assertEq(token.balanceOf(alice), 100);
    }

    function testWithdrawCreationFee_FailsIfCallerIsNotOwner() public {
        vm.prank(alice);
        // CHECK: tx reverts
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector, alice
            )
        );
        factory.withdrawCreationFee(token, alice);
    }

    function testWithdrawPimFee() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();

        (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
        factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );
        address fundingManager = address(orchestrator.fundingManager());

        // CHECK: bonding curve EMITS event for fee withdrawal
        vm.expectEmit(true, true, true, false);
        emit IBondingCurveBase_v1.ProjectCollateralFeeWithdrawn(
            address(this), 0
        );
        vm.expectEmit(true, true, true, true);
        emit IPIM_WorkflowFactory_v1.CreationFeeWithdrawn(
            fundingManager, alice, 0
        );
        factory.withdrawPimFee(fundingManager, alice);
    }

    function testWithdrawPimFee__FailsIfCallerIsNotPimFeeRecipient() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();

        (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        address fundingManager = address(orchestrator.fundingManager());
        // CHECK: withdrawal REVERTS if caller IS NOT the fee recipient
        vm.expectRevert(
            abi.encodeWithSelector(
                IPIM_WorkflowFactory_v1
                    .PIM_WorkflowFactory__OnlyPimFeeRecipient
                    .selector
            )
        );
        vm.prank(alice);
        factory.withdrawPimFee(fundingManager, alice);
    }

    function testTransferPimFeeEligibility() public {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();

        (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        address fundingManager = address(orchestrator.fundingManager());
        // CHECK: when fee recipient is updated event is emitted
        vm.expectEmit(true, true, true, true);
        emit IPIM_WorkflowFactory_v1.PimFeeRecipientUpdated(
            address(this), alice
        );
        factory.transferPimFeeEligibility(fundingManager, alice);

        // CHECK: new recipient (alice) CAN withdraw fee
        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit IBondingCurveBase_v1.ProjectCollateralFeeWithdrawn(
            address(this), 0
        );
        factory.withdrawPimFee(fundingManager, alice);
    }

    function testTransferPimFeeEligibility_FailsIfCallerIsNotPimFeeRecipient()
        public
    {
        IPIM_WorkflowFactory_v1.PIMConfig memory pimConfig =
            getDefaultPIMConfig();

        (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
            workflowConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            pimConfig
        );

        address fundingManager = address(orchestrator.fundingManager());
        // CHECK: withdrawal REVERTS if caller IS NOT the fee recipient
        vm.expectRevert(
            abi.encodeWithSelector(
                IPIM_WorkflowFactory_v1
                    .PIM_WorkflowFactory__OnlyPimFeeRecipient
                    .selector
            )
        );
        vm.prank(alice);
        factory.transferPimFeeEligibility(fundingManager, address(0xB0B));
    }

    // UTILS
    function getDefaultPIMConfig()
        internal
        view
        returns (IPIM_WorkflowFactory_v1.PIMConfig memory)
    {
        return IPIM_WorkflowFactory_v1.PIMConfig({
            fundingManagerMetadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
            authorizerMetadata: roleAuthorizerMetadata,
            bcProperties: bcProperties,
            issuanceTokenParams: issuanceTokenParams,
            collateralToken: address(token),
            admin: address(this),
            recipient: alice,
            isRenouncedIssuanceToken: true,
            isRenouncedWorkflow: true,
            withInitialLiquidity: true
        });
    }
}
