// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IRestricted_PIM_Factory_v1} from
    "src/factories/interfaces/IRestricted_PIM_Factory_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {Restricted_PIM_Factory_v1} from
    "src/factories/custom/Restricted_PIM_Factory_v1.sol";
import {E2ETest} from "test/e2e/E2ETest.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {EventHelpers} from "test/utils/helpers/EventHelpers.sol";
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {IOwnable} from "@ex/interfaces/IOwnable.sol";

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract Restricted_PIM_Factory_v1Test is E2ETest {
    // SuT
    Restricted_PIM_Factory_v1 factory;

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

    // addresses
    address admin = vm.addr(420);
    address actor = address(this);
    address sponsor = vm.addr(1);
    address mockTrustedForwarder = vm.addr(3);

    // bc params
    uint initialIssuuanceSupply = 122_727_272_727_272_727_272_727;
    uint initialCollateralSupply = 3_163_408_614_166_851_161;
    uint32 reserveRatio = 160_000;

    function setUp() public override {
        super.setUp();

        // deploy new factory
        factory = new Restricted_PIM_Factory_v1(
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
            roleAuthorizerMetadata, abi.encode(address(admin))
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
            restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata,
            abi.encode(address(0), bcProperties, token)
        );

        // Assemble bonding curve params
        issuanceTokenParams = IBondingCurveBase_v1.IssuanceToken({
            name: "Bonding Curve Token",
            symbol: "BCT",
            decimals: 18,
            maxSupply: type(uint).max - 1
        });

        // mint collateral token to deployer and approve to factory
        token.mint(admin, type(uint).max);
    }

    /* Test addFunding
        └── given that token has been approved
        |   └── when called
        |       └── then it sends collateral tokens from sender to factory
        |       └── then emits an event
        └── given that token has NOT been approved
            └── when called
                └── then it reverts
    */
    function testAddFunding() public {
        vm.startPrank(admin);

        token.approve(address(factory), initialCollateralSupply);

        // CHECK: event is emitted
        vm.expectEmit(true, true, true, true);
        emit IRestricted_PIM_Factory_v1.FundingAdded(
            admin, actor, address(token), initialCollateralSupply
        );

        factory.addFunding(actor, address(token), initialCollateralSupply);

        // CHECK: factory HOLDS collateral tokens
        assertEq(token.balanceOf(address(factory)), initialCollateralSupply);
        vm.stopPrank();
    }

    function testAddFunding_WithoutApproval() public {
        vm.startPrank(admin);
        vm.expectRevert();
        factory.addFunding(actor, address(token), initialCollateralSupply);
    }

    /* Test withdrawFunding
        └── given that caller had added funding before
        |   └── when called
        |       └── then it withdraws tokens from factory
        |       └── then emits an event
        └── given that caller had NOT added funding before (trying to steal someones funding)
            └── when called
                └── then it reverts
    */
    function testWithdrawFunding() public {
        vm.startPrank(admin);
        token.approve(address(factory), initialCollateralSupply);
        factory.addFunding(actor, address(token), initialCollateralSupply);

        // CHECK: event is emitted
        vm.expectEmit(true, true, true, true);
        emit IRestricted_PIM_Factory_v1.FundingRemoved(
            admin, actor, address(token), initialCollateralSupply
        );

        // CHECK: factory DOES NOT hold collateral tokens
        factory.withdrawFunding(actor, address(token), initialCollateralSupply);
        assertEq(token.balanceOf(address(factory)), 0);
        vm.stopPrank();
    }

    function testWithdrawFunding_AsThief() public {
        vm.startPrank(admin);
        token.approve(address(factory), initialCollateralSupply);
        factory.addFunding(actor, address(token), initialCollateralSupply);
        vm.stopPrank();

        address thief = vm.addr(69);
        vm.startPrank(thief);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRestricted_PIM_Factory_v1.InsufficientFunding.selector, 0
            )
        );
        factory.withdrawFunding(actor, address(token), initialCollateralSupply);
        vm.stopPrank();
    }

    /* Test createPIMWorkflow
        └── given that the curve creation has been funded
        |   └── when called
        |       └── then it mints initial issuance supply to admin
        |       └── then it transfers initial collateral supply from sponsor to bonding curve
        |       └── then it revokes issuanceToken minting rights from factory
        |       └── then it grants issuanceToken minting rights to mint wrapper
        |       └── then it grants minting minting rights on mint wrapper to bonding curve
        |       └── then it grants curve interaction role to admin
        |       └── then it transfers ownership of mint wrapper to admin
        |       └── then it renounces ownership of issuance token
        |       └── then it revokes orchestrator admin rights from factory and transfers them to admin
        |       └── then it emits a PIMWorkflowCreated event
        └── given that there is no funding
        |   └── when called
        |       └── then it reverts
    */

    function testCreatePIMWorkflow_WithFunding() public {
        // add funding
        vm.startPrank(admin);
        token.approve(address(factory), initialCollateralSupply);
        factory.addFunding(actor, address(token), initialCollateralSupply);
        vm.stopPrank();

        // start recording logs
        vm.recordLogs();

        IOrchestrator_v1 orchestrator = factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // get issuance token address from event
        (bool emitted, bytes32 eventTopic) = eventHelpers.getEventTopic(
            IRestricted_PIM_Factory_v1.PIMWorkflowCreated.selector, logs, 2
        );
        address issuanceTokenAddress =
            eventHelpers.getAddressFromTopic(eventTopic);
        address mintWrapperAddress = IBondingCurveBase_v1(
            address(orchestrator.fundingManager())
        ).getIssuanceToken();

        // CHECK: PIMWorkflowCreated event is emitted
        assertTrue(emitted);

        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(issuanceTokenAddress);
        address fundingManager = address(orchestrator.fundingManager());
        // CHECK: admin RECEIVES initial issuance supply
        assertEq(
            issuanceToken.balanceOf(actor), bcProperties.initialIssuanceSupply
        );
        // CHECK: bonding curve HOLDS initial collateral supply
        assertEq(
            token.balanceOf(fundingManager),
            bcProperties.initialCollateralSupply
        );
        // CHECK: factory DOES NOT have minting rights on token anymore
        assertFalse(issuanceToken.allowedMinters(address(factory)));
        // CHECK: mint wrapper HAS minting rights on token
        assertTrue(issuanceToken.allowedMinters(mintWrapperAddress));
        // CHECK: bonding curve HAS minting rights on mint wrapper
        assertTrue(
            IERC20Issuance_v1(mintWrapperAddress).allowedMinters(fundingManager)
        );
        // CHECK: initialAdmin HAS curve interaction role
        bytes32 curveInteractionRole =
        IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
            .CURVE_INTERACTION_ROLE();
        bytes32 curveInteractionRoleId = orchestrator.authorizer()
            .generateRoleId(fundingManager, curveInteractionRole);
        assertTrue(
            orchestrator.authorizer().checkForRole(
                curveInteractionRoleId, actor
            )
        );
        // CHECK: issuance token HAS NO owner
        assertEq(issuanceToken.owner(), address(0));
        // CHECK: initialAdmin IS owner of mint wrapper
        assertEq(IOwnable(mintWrapperAddress).owner(), admin);
        // CHECK: initialAdmin IS orchestrator admin
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        assertTrue(orchestrator.authorizer().hasRole(adminRole, admin));
        // CHECK: factory DOES NOT have admin rights over workflow
        assertFalse(
            orchestrator.authorizer().hasRole(adminRole, address(factory))
        );
    }

    function testCreatePIMWorkflow_WithoutFunding() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRestricted_PIM_Factory_v1.InsufficientFunding.selector, 0
            )
        );
        factory.createPIMWorkflow(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            logicModuleConfigs,
            issuanceTokenParams
        );
    }
}
