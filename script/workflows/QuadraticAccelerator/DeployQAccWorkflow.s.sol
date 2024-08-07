// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Script Dependencies
import {TestnetDeploymentScript} from
    "script/deploymentScript/TestnetDeploymentScript.s.sol";

// Internal InterfacesF
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {ILM_PC_PaymentRouter_v1} from
    "@lm/interfaces/ILM_PC_PaymentRouter_v1.sol";

import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract DeployQAccWorkflow is
    TestnetDeploymentScript //@todo: remove
{
    //NOTE: This script assumes an exisiting orchestratorFactory. If there is none, it will create a testnetDeployment first

    //-------------------------------------------------------------------------
    // Storage

    ERC20Mock public orchestratorToken;
    ERC20Issuance_v1 public issuanceToken;
    IOrchestrator_v1 public test_orchestrator;

    address[] initialAuthorizedAddresses;

    function run() public virtual override {
        if (orchestratorFactory == address(0)) {
            super.run();
        }
        //super.run();

        setupOrchestrator();
    }

    function setupOrchestrator() public {
        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Deploy the issacne token  and set it up
        vm.startBroadcast(deployerPrivateKey);
        {
            issuanceToken = new ERC20Issuance_v1(
                "QAcc Project Token",
                "QACC",
                18,
                type(uint).max - 1,
                address(this) // assigns owner role to itself initially to manage minting rights temporarily
            );
        }
        vm.stopBroadcast();

        //mint deployer lots of tokens to test
        mockCollateralToken.mint(deployer, 100e18);
        uint initialBuyAmount = 10e18;

        // Define bondign curve properties:
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 200_000,
                reserveRatioForSelling: 200_000,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 100,
                initialCollateralSupply: 100
            });

        // define token to be used as collateral
        orchestratorToken = mockCollateralToken;

        // Orchestrator_v1
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        // Funding Manager: Metadata, token address //@todo wait for DepositVault
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata,
            abi.encode(address(issuanceToken), bc_properties, orchestratorToken)
        );

        // Payment Processor: only Metadata
        IOrchestratorFactory_v1.ModuleConfig memory
            paymentProcessorFactoryConfig = IOrchestratorFactory_v1
                .ModuleConfig(streamingPaymentProcessorMetadata, bytes(""));

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            roleAuthorizerMetadata,
            abi.encode(deployer) //@todo Admin address?
        );

        // PaymentRouter: none
        IOrchestratorFactory_v1.ModuleConfig memory paymentRouterFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            paymentRouterMetadata, abi.encode("")
        );

        // Add the configuration for all the non-mandatory modules. In this case only the PaymentRouter.
        IOrchestratorFactory_v1.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory_v1.ModuleConfig[](1);
        additionalModuleConfig[0] = paymentRouterFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator_v1 Creation

        vm.startBroadcast(deployerPrivateKey);
        {
            test_orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
                .createOrchestrator(
                workflowConfig,
                fundingManagerFactoryConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Now we need to find the BountyManager. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the BountyManager.

        ILM_PC_PaymentRouter_v1 paymentRouter;

        bytes4 ILM_PC_PaymentRouter_v1InterfaceId =
            type(ILM_PC_PaymentRouter_v1).interfaceId;
        address[] memory modulesList = test_orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    ILM_PC_PaymentRouter_v1InterfaceId
                )
            ) {
                paymentRouter = ILM_PC_PaymentRouter_v1(modulesList[i]);
                break;
            }
        }

        console2.log("\n\n");
        console2.log(
            "=================================================================================="
        );
        console2.log(
            "Orchestrator_v1 with Id %s created at address: %s ",
            test_orchestrator.orchestratorId(),
            address(test_orchestrator)
        );
        console2.log(
            "\t-FundingManager deployed at address: %s ",
            address(test_orchestrator.fundingManager())
        );
        console2.log(
            "\t-Authorizer deployed at address: %s ",
            address(test_orchestrator.authorizer())
        );
        console2.log(
            "\t-PaymentProcessor deployed at address: %s ",
            address(test_orchestrator.paymentProcessor())
        );

        console2.log(
            "\t-LM_PC_PaymentRouter_v1 deployed at address: %s ",
            address(paymentRouter)
        );
        console2.log(
            "=================================================================================="
        );

        // TODO: Sort out authorizations

        // get bonding curve / funding manager
        address fundingManager = address(test_orchestrator.fundingManager());

        // enable bonding curve to mint issuance token
        issuanceToken.setMinter(fundingManager, true);

        issuanceToken.setMinter(deployer, true);

        // we mint the initial supply as deployer

        issuanceToken.mint(deployer, bc_properties.initialIssuanceSupply);

        // give allowance to the bonding curve to spend deployer funds
        vm.startBroadcast(deployerPrivateKey);
        {
            //Allow the deployer to buy tokens
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .grantModuleRole(
                FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                    fundingManager
                ).CURVE_INTERACTION_ROLE(),
                deployer
            );

            // Set up initial supply and balance
            mockCollateralToken.transfer(
                fundingManager, bc_properties.initialCollateralSupply
            );

            // Performt the initial buy
            mockCollateralToken.approve(
                address(fundingManager), initialBuyAmount
            );
            IBondingCurveBase_v1(fundingManager).buyFor(
                deployer, initialBuyAmount, 1
            );
        }
        vm.stopBroadcast();

        // From now on only the curve has minting rights
        issuanceToken.setMinter(deployer, false);

        // The deployer is the owner of the issuance token
        issuanceToken.transferOwnership(deployer);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _manageInitialSupplies(
        IBondingCurveBase_v1 fundingManager,
        IERC20 collateralToken,
        ERC20Issuance_v1 issuanceToken,
        uint initialCollateralSupply,
        uint initialIssuanceSupply,
        address recipient
    ) private {
        // collateral token is paid for by the msg.sender
        collateralToken.transferFrom(
            deployer, address(fundingManager), initialCollateralSupply
        );
        // issuance token is minted to the the specified recipient
        issuanceToken.mint(recipient, initialIssuanceSupply);
    }

    function _manageInitialPurchase(
        IBondingCurveBase_v1 fundingManager,
        IERC20 collateralToken,
        uint firstCollateralIn,
        address recipient
    ) private {
        // transfer initial collateral amount from deployer to factory
        collateralToken.transferFrom(deployer, address(this), firstCollateralIn);

        // set allowance for curve to spend factory's tokens
        collateralToken.approve(address(fundingManager), firstCollateralIn);

        // make first purchase
        IBondingCurveBase_v1(fundingManager).buyFor(
            recipient, firstCollateralIn, 1
        );
    }

    function _transferTokenOwnership(
        ERC20Issuance_v1 issuanceToken,
        address newAdmin
    ) private {
        if (newAdmin == address(0)) {
            issuanceToken.renounceOwnership();
        } else {
            issuanceToken.transferOwnership(newAdmin);
        }
    }

    function _transferWorkflowAdminRights(
        IOrchestrator_v1 orchestrator,
        address newAdmin
    ) private {
        bytes32 adminRole = orchestrator.authorizer().getAdminRole();
        // if renounced flag is set, add zero address as admin (because workflow must have at least one admin set)
        orchestrator.authorizer().grantRole(adminRole, newAdmin);
        // and revoke admin role from factory
        orchestrator.authorizer().revokeRole(adminRole, address(this));
    }
}
