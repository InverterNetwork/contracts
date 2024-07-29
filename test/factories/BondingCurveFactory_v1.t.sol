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

    // Helpers
    EventHelpers eventHelpers;

    IOrchestratorFactory_v1.WorkflowConfig workflowConfig;
    IOrchestratorFactory_v1.ModuleConfig authorizerConfig;
    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig;
    IOrchestratorFactory_v1.ModuleConfig[] logicModuleConfigs;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties bcProperties;
    IBondingCurveFactory_v1.IssuanceTokenParams issuanceTokenParams;

    address mockDeployer = vm.addr(1);
    uint initialCollateral = 3;

    event BcPimCreated(address indexed issuanceToken);

    function setUp() public override {
        super.setUp();
        eventHelpers = new EventHelpers();

        // deploy new factory
        factory = new BondingCurveFactory_v1(address(orchestratorFactory));

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
            initialAdmin: mockDeployer
        });

        // mint collateral token to deployer and approve to factory
        token.mint(address(this), initialCollateral);
        token.approve(address(factory), initialCollateral);
    }

    function testCreateBondingCurve_Renounced() public {
        vm.recordLogs();

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
                isRenounced: true
            })
        );

        // check that token is deployed and initial amount is minted
        assertEq(
            issuanceToken.balanceOf(mockDeployer),
            bcProperties.initialIssuanceSupply
        );

        // check that minting rights for factory have been revoked
        bool isFactoryStillMinter =
            issuanceToken.allowedMinters(address(factory));
        assertFalse(isFactoryStillMinter);

        // check that minting rights for bonding curve module have been granted
        bool isBcMinter = issuanceToken.allowedMinters(
            address(orchestrator.fundingManager())
        );
        assertTrue(isBcMinter);

        // check that control over token and workflow have been renounced
        address owner = issuanceToken.owner();
        assertEq(owner, address(0));
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isDeployerAdmin =
            orchestrator.authorizer().hasRole(adminRole, address(factory));
        assertFalse(isDeployerAdmin);
    }

    function testCreateBondingCurve_NotRenounced() public {
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
                isRenounced: false
            })
        );

        assertEq(issuanceToken.owner(), mockDeployer);
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        bool isDeployerAdmin =
            orchestrator.authorizer().hasRole(adminRole, address(mockDeployer));
        assertTrue(isDeployerAdmin);
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
                isRenounced: true
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
                isRenounced: true
            })
        );
    }
}
