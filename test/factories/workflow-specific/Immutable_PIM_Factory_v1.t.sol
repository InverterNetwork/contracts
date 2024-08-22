// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IImmutable_PIM_Factory_v1} from
    "src/factories/interfaces/IImmutable_PIM_Factory_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {Immutable_PIM_Factory_v1} from
    "src/factories/workflow-specific/Immutable_PIM_Factory_v1.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {EventHelpers} from "test/utils/helpers/EventHelpers.sol";

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract Immutable_PIM_Factory_v1Test is E2ETest {
    // SuT
    Immutable_PIM_Factory_v1 factory;

    // helpers
    EventHelpers eventHelpers;

    // Deployment Parameters
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveBase_v1.IssuanceToken issuanceTokenParams;
    uint initialPurchaseAmount = 100 ether;

    // addresses
    address workflowAdmin = vm.addr(420);
    address factoryDeployer = vm.addr(1);
    address workflowDeployer = vm.addr(2);
    address mockTrustedForwarder = vm.addr(3);
    address alice = vm.addr(0xA11CE);

    // bc params
    uint initialIssuuanceSupply = 122_727_272_727_272_727_272_727;
    uint initialCollateralSupply = 3_163_408_614_166_851_161;
    uint32 reserveRatio = 160_000;

    function setUp() public override {
        super.setUp();

        // deploy new factory
        factory = new Immutable_PIM_Factory_v1(
            address(orchestratorFactory), mockTrustedForwarder
        );

        eventHelpers = new EventHelpers();

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
            bancorVirtualSupplyBondingCurveFundingManagerMetadata,
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
    }

    /* Test createPIMWorkflow
        └── given an unrestricted bonding curve
            └── when called
                └── then it deploys an issuance token and a workflow
                └── then it executes initial purchase
                └── then it grants issuanceToken minting rights to bonding curve
                └── then it renounces ownership over issuance token
                └── then it revokes orchestrator admin rights and transfers them to factory
                └── then it emits a PIMWorkflowCreated event YES
    */

    function testCreatePIMWorkflow() public {
        // start recording logs
        vm.recordLogs();

        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // get issuance token address from event
        (bool emitted, bytes32 eventTopic) = eventHelpers.getEventTopic(
            IImmutable_PIM_Factory_v1.PIMWorkflowCreated.selector, logs, 2
        );
        address issuanceTokenAddress =
            eventHelpers.getAddressFromTopic(eventTopic);

        // CHECK: PIMWorkflowCreated event is emitted
        assertTrue(emitted);

        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(issuanceTokenAddress);
        address fundingManager = address(orchestrator.fundingManager());

        // CHECK: factory DOES NOT have minting rights on token anymore
        assertFalse(issuanceToken.allowedMinters(address(factory)));
        // CHECK: bonding curve module HAS minting rights on token
        assertTrue(issuanceToken.allowedMinters(fundingManager));
        // CHECK: issuance token is renounced
        assertEq(issuanceToken.owner(), address(0));
        // CHECK: factory HAS admin rights over workflow
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertTrue(
            orchestrator.authorizer().hasRole(adminRole, address(factory))
        );
        // CHECK: initial purchase was executed
        assertGt(issuanceToken.balanceOf(workflowAdmin), 0);
        assertEq(token.balanceOf(fundingManager), initialPurchaseAmount);
    }

    /* Test testWithdrawPimFee
        ├── given the msg.sender is the fee recipient
        |   └── when called
        |       └── then it emits fee claim events on bc and factory
        └── given the msg.sender is NOT the fee recipient
            └── when called
                └── then it reverts   
    */

    function testWithdrawPimFee() public {
        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );
        address fundingManager = address(orchestrator.fundingManager());
        vm.startPrank(workflowAdmin);
        // CHECK: bonding curve EMITS event for fee withdrawal
        vm.expectEmit(true, true, true, false);
        emit IBondingCurveBase_v1.ProjectCollateralFeeWithdrawn(
            address(this), 0
        );
        uint claimableFees = IBondingCurveBase_v1(fundingManager).projectCollateralFeeCollected();
        vm.expectEmit(true, false, false, false);
        emit IImmutable_PIM_Factory_v1.PimFeeClaimed(
            fundingManager, address(this), alice, claimableFees
        );
        factory.withdrawPimFee(fundingManager, alice);
        vm.stopPrank();
    }

    function testWithdrawPimFee__FailsIfCallerIsNotPimFeeRecipient() public {
        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams,
            initialPurchaseAmount
        );
        address fundingManager = address(orchestrator.fundingManager());

        // CHECK: withdrawal REVERTS if caller IS NOT the fee recipient
        vm.expectRevert(
            abi.encodeWithSelector(
                IImmutable_PIM_Factory_v1
                    .PIM_WorkflowFactory__OnlyPimFeeRecipient
                    .selector
            )
        );
        vm.prank(alice);
        factory.withdrawPimFee(fundingManager, alice);
    }
}
