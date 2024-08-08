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

    function testCreatePIMWorkflow() public {
        // CHECK: event is emitted
        vm.expectEmit(false, false, false, false);
        emit IRestricted_PIM_Factory_v1.PIMWorkflowCreated(
            address(0), address(0), address(0)
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
    }

    // function testCreatePIMWorkflow_WithInitialLiquidity() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();
    //     pimConfig.withInitialLiquidity = true; // just to highlight what is being tested

    //     (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
    //     factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );
    //     address fundingManager = address(orchestrator.fundingManager());

    //     // CHECK: curve HAS received initial collateral supply and firstCollateralIn
    //     assertTrue(
    //         token.balanceOf(fundingManager)
    //             == pimConfig.bcProperties.initialCollateralSupply
    //                 + pimConfig.firstCollateralIn
    //     );
    //     // CHECK: recipient receives initialIssuanceSupply plus first purchase amount
    //     assertGt(
    //         issuanceToken.balanceOf(pimConfig.recipient),
    //         bcProperties.initialIssuanceSupply
    //     );
    //     // CHECK: if recipient SELLS complete stack and BUYS BACK they get same amount of issuanceToken
    //     vm.startPrank(pimConfig.recipient);
    //     // get issuance balance before sale and rebuy
    //     uint balanceBefore = issuanceToken.balanceOf(pimConfig.recipient);
    //     // get static price before sale
    //     uint staticPriceBefore =
    //         IBondingCurveBase_v1(fundingManager).getStaticPriceForBuying();
    //     // get how many issuance tokens are sold
    //     uint firstPurchaseVolume =
    //         balanceBefore - pimConfig.bcProperties.initialIssuanceSupply;
    //     issuanceToken.approve(fundingManager, firstPurchaseVolume);
    //     uint collateralAmountOut = IRedeemingBondingCurveBase_v1(fundingManager)
    //         .calculateSaleReturn(firstPurchaseVolume);
    //     // sell all tokens from initial purchase (the one that happened atomically in the factory)
    //     IRedeemingBondingCurveBase_v1(fundingManager).sell(
    //         firstPurchaseVolume, collateralAmountOut
    //     );
    //     // alice only has initial issuance supply left?
    //     assert(
    //         issuanceToken.balanceOf(pimConfig.recipient)
    //             == pimConfig.bcProperties.initialIssuanceSupply
    //     );
    //     token.approve(fundingManager, collateralAmountOut);
    //     uint issuanceAmountOut = IBondingCurveBase_v1(fundingManager)
    //         .calculatePurchaseReturn(collateralAmountOut);
    //     // now use the collateral from the sale to buy back
    //     IBondingCurveBase_v1(fundingManager).buy(
    //         collateralAmountOut, issuanceAmountOut
    //     );
    //     // get the static price after the re-buy
    //     uint staticPriceAfter =
    //         IBondingCurveBase_v1(fundingManager).getStaticPriceForBuying();
    //     // CHECK: if recipient SELLS complete stack and BUYS BACK they end up with same balance of issuanceToken
    //     assertApproxEqRel(
    //         balanceBefore,
    //         issuanceToken.balanceOf(pimConfig.recipient),
    //         0.00001e18
    //     );
    //     // CHECK: if recipient SELLS complete stack and BUYS BACK the static price is the same again
    //     assertEq(staticPriceBefore, staticPriceAfter);
    //     vm.stopPrank();
    // }

    // function testCreatePIMWorkflow_WithoutInitialLiquidity() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();
    //     pimConfig.withInitialLiquidity = false;

    //     uint preCollateralBalance = token.balanceOf(address(this));

    //     (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
    //     factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     uint postCollateralBalance = token.balanceOf(address(this));

    //     address fundingManager = address(orchestrator.fundingManager());

    //     // CHECK: deployer DID NOT send initial collateral supply to curve, ONLY did first purchase
    //     assertEq(
    //         preCollateralBalance - postCollateralBalance,
    //         pimConfig.firstCollateralIn
    //     );
    //     // CHECK: initialIssuanceSupply is BURNT (sent to 0xDEAD)
    //     assertEq(
    //         issuanceToken.balanceOf(address(0xDEAD)),
    //         bcProperties.initialIssuanceSupply
    //     );
    //     // CHECK: recipient receives some amount of issuanceToken (due to first purchase)
    //     assertTrue(issuanceToken.balanceOf(pimConfig.recipient) > 0);

    //     vm.startPrank(pimConfig.recipient);
    //     // get issuance balance before sale and rebuy
    //     uint balanceBefore = issuanceToken.balanceOf(pimConfig.recipient);
    //     // get static price before sale
    //     uint staticPriceBefore =
    //         IBondingCurveBase_v1(fundingManager).getStaticPriceForBuying();
    //     issuanceToken.approve(fundingManager, balanceBefore);
    //     uint collateralAmountOut = IRedeemingBondingCurveBase_v1(fundingManager)
    //         .calculateSaleReturn(balanceBefore);
    //     // use complete issuance balance to sell for collateral
    //     IRedeemingBondingCurveBase_v1(fundingManager).sell(
    //         balanceBefore, collateralAmountOut
    //     );
    //     // alice doesn't have any issuance token left
    //     assert(issuanceToken.balanceOf(pimConfig.recipient) == 0);
    //     token.approve(fundingManager, collateralAmountOut);
    //     uint issuanceAmountOut = IBondingCurveBase_v1(fundingManager)
    //         .calculatePurchaseReturn(collateralAmountOut);
    //     // now use the collateral from the sale to buy back
    //     IBondingCurveBase_v1(fundingManager).buy(
    //         collateralAmountOut, issuanceAmountOut
    //     );
    //     uint staticPriceAfter =
    //         IBondingCurveBase_v1(fundingManager).getStaticPriceForBuying();
    //     // CHECK: if recipient SELLS complete stack and BUYS BACK they end up with same balance of issuanceToken
    //     assertApproxEqRel(
    //         balanceBefore,
    //         issuanceToken.balanceOf(pimConfig.recipient),
    //         0.00001e18
    //     );
    //     // CHECK: if recipient SELLS complete stack and BUYS BACK the static price is the same again
    //     assertEq(staticPriceBefore, staticPriceAfter);
    //     vm.stopPrank();
    // }

    // function testCreatePIMWorkflow_IfFullyRenounced() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();
    //     pimConfig.isRenouncedIssuanceToken = true;
    //     pimConfig.isRenouncedWorkflow = true;

    //     (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
    //     factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     // CHECK: the token DOES NOT have an owner anymore
    //     address owner = issuanceToken.owner();
    //     assertEq(owner, address(0));
    //     // CHECK: the deployer DOES NOT get admin rights over workflow
    //     bytes32 adminRole = orchestrator.authorizer().getAdminRole();
    //     bool isDeployerAdmin = orchestrator.authorizer().hasRole(
    //         adminRole, address(workflowDeployer)
    //     );
    //     assertFalse(isDeployerAdmin);
    //     // CHECK: the factory HAS admin rights over workflow
    //     bool isFactoryAdmin =
    //         orchestrator.authorizer().hasRole(adminRole, address(factory));
    //     assertTrue(isFactoryAdmin);
    // }

    // function testCreatePIMWorkflow_IfNotRenounced() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();
    //     pimConfig.isRenouncedIssuanceToken = false;
    //     pimConfig.isRenouncedWorkflow = false;
    //     pimConfig.recipient = alice;
    //     pimConfig.admin = workflowDeployer;

    //     (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
    //     factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     // CHECK: the deployer IS owner of the token
    //     assertEq(issuanceToken.owner(), workflowDeployer);
    //     // CHECK: the deployer IS admin of the workflow
    //     bytes32 adminRole = orchestrator.authorizer().getAdminRole();
    //     bool isDeployerAdmin = orchestrator.authorizer().hasRole(
    //         adminRole, address(workflowDeployer)
    //     );
    //     assertTrue(isDeployerAdmin);
    // }

    // function testCreatePIMWorkflow_IfTokenRenounced() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();
    //     pimConfig.isRenouncedIssuanceToken = true;
    //     pimConfig.isRenouncedWorkflow = false;
    //     pimConfig.recipient = alice;
    //     pimConfig.admin = workflowDeployer;

    //     (IOrchestrator_v1 orchestrator, ERC20Issuance_v1 issuanceToken) =
    //     factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     // CHECK: the token DOES NOT have an owner anymore
    //     assertEq(issuanceToken.owner(), address(0));
    //     // CHECK: the deployer IS admin of the workflow
    //     bytes32 adminRole = orchestrator.authorizer().getAdminRole();
    //     bool isDeployerAdmin = orchestrator.authorizer().hasRole(
    //         adminRole, address(workflowDeployer)
    //     );
    //     assertTrue(isDeployerAdmin);
    // }

    // function testCreatePIMWorkflow_IfWorkflowRenounced() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();
    //     pimConfig.isRenouncedIssuanceToken = false;
    //     pimConfig.isRenouncedWorkflow = true;

    //     (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     // CHECK: the deployer IS owner of the token
    //     // assertEq(issuanceToken.owner(), workflowDeployer);
    //     // CHECK: the deployer DOES NOT have admin rights over workflow
    //     bytes32 adminRole = orchestrator.authorizer().getAdminRole();
    //     bool isDeployerAdmin = orchestrator.authorizer().hasRole(
    //         adminRole, address(workflowDeployer)
    //     );
    //     assertFalse(isDeployerAdmin);
    //     // CHECK: the factory DOES have admin rights over workflow
    //     bool isFactoryAdmin =
    //         orchestrator.authorizer().hasRole(adminRole, address(factory));
    //     assertTrue(isFactoryAdmin);
    // }

    // function testCreatePIMWorkflow_FailsWithoutCollateralTokenApproval()
    //     public
    // {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();
    //     address deployer = address(0xB0B);
    //     vm.prank(deployer);

    //     vm.expectRevert();

    //     factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );
    // }

    // /* Test testWithdrawPimFee
    //     ├── given the msg.sender is the fee recipient
    //     |   └── when called
    //     |       └── then it emits fee claim events on bc and factory
    //     └── given the msg.sender is NOT the fee recipient
    //         └── when called
    //             └── then it reverts
    // */

    // function testWithdrawPimFee() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();

    //     (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );
    //     address fundingManager = address(orchestrator.fundingManager());

    //     // CHECK: bonding curve EMITS event for fee withdrawal
    //     vm.expectEmit(true, true, true, false);
    //     emit IBondingCurveBase_v1.ProjectCollateralFeeWithdrawn(
    //         address(this), 0
    //     );
    //     vm.expectEmit(true, true, true, false);
    //     emit IRestricted_PIM_Factory_v1.PimFeeClaimed(
    //         fundingManager, address(this), alice, 0
    //     );
    //     factory.withdrawPimFee(fundingManager, alice);
    // }

    // function testWithdrawPimFee__FailsIfCallerIsNotPimFeeRecipient() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();

    //     (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     address fundingManager = address(orchestrator.fundingManager());
    //     // CHECK: withdrawal REVERTS if caller IS NOT the fee recipient
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IRestricted_PIM_Factory_v1
    //                 .PIM_WorkflowFactory__OnlyPimFeeRecipient
    //                 .selector
    //         )
    //     );
    //     vm.prank(alice);
    //     factory.withdrawPimFee(fundingManager, alice);
    // }

    // /* Test testTransferPimFeeEligibility
    //     ├── given the msg.sender is the fee recipient
    //     |   └── when called
    //     |       └── then it emits an event indicating role update and lets new recipient withdraw fee
    //     └── given the msg.sender is NOT the fee recipient
    //        └── when called
    //             └── then it reverts
    // */

    // function testTransferPimFeeEligibility() public {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();

    //     (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     address fundingManager = address(orchestrator.fundingManager());
    //     // CHECK: when fee recipient is updated event is emitted
    //     vm.expectEmit(true, true, true, true);
    //     emit IRestricted_PIM_Factory_v1.PimFeeRecipientUpdated(
    //         address(this), alice
    //     );
    //     factory.transferPimFeeEligibility(fundingManager, alice);

    //     // CHECK: new recipient (alice) CAN withdraw fee
    //     vm.prank(alice);
    //     vm.expectEmit(true, true, true, false);
    //     emit IBondingCurveBase_v1.ProjectCollateralFeeWithdrawn(
    //         address(this), 0
    //     );
    //     factory.withdrawPimFee(fundingManager, alice);
    // }

    // function testTransferPimFeeEligibility_FailsIfCallerIsNotPimFeeRecipient()
    //     public
    // {
    //     IRestricted_PIM_Factory_v1.PIMConfig memory pimConfig =
    //         getDefaultPIMConfig();

    //     (IOrchestrator_v1 orchestrator,) = factory.createPIMWorkflow(
    //         workflowConfig,
    //         paymentProcessorConfig,
    //         logicModuleConfigs,
    //         pimConfig
    //     );

    //     address fundingManager = address(orchestrator.fundingManager());
    //     // CHECK: withdrawal REVERTS if caller IS NOT the fee recipient
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IRestricted_PIM_Factory_v1
    //                 .PIM_WorkflowFactory__OnlyPimFeeRecipient
    //                 .selector
    //         )
    //     );
    //     vm.prank(alice);
    //     factory.transferPimFeeEligibility(fundingManager, address(0xB0B));
    // }

    // UTILS
    // function getDefaultPIMConfig()
    //     internal
    //     view
    //     returns (IRestricted_PIM_Factory_v1.PIMConfig memory)
    // {
    //     return IRestricted_PIM_Factory_v1.PIMConfig({
    //         fundingManagerMetadata: bancorVirtualSupplyBondingCurveFundingManagerMetadata,
    //         authorizerMetadata: roleAuthorizerMetadata,
    //         bcProperties: bcProperties,
    //         issuanceTokenParams: issuanceTokenParams,
    //         collateralToken: address(token),
    //         firstCollateralIn: firstCollateralIn,
    //         admin: address(this),
    //         recipient: alice,
    //         isRenouncedIssuanceToken: true,
    //         isRenouncedWorkflow: true,
    //         withInitialLiquidity: true
    //     });
    // }
}
