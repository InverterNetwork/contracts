// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Import interfaces:

import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// Import scripts:
import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";
import {DeployModuleFactory_v1} from
    "script/factories/DeployModuleFactory_v1.s.sol";
import {DeployOrchestratorFactory_v1} from
    "script/factories/DeployOrchestratorFactory_v1.s.sol";
import {DeployLM_PC_Bounties_v1} from
    "script/modules/logicModule/DeployLM_PC_Bounties_v1.s.sol";

import {DeployGovernor_v1} from "script/external/DeployGovernor_v1.s.sol";
import {DeployFeeManager_v1} from "script/external/DeployFeeManager_v1.s.sol";
import {DeployTransactionForwarder_v1} from
    "script/external/DeployTransactionForwarder_v1.s.sol";
import {DeployOrchestrator_v1} from
    "script/orchestrator/DeployOrchestrator_v1.s.sol";
import {DeployPP_Simple_v1} from
    "script/modules/paymentProcessor/DeployPP_Simple_v1.s.sol";
import {DeployFM_Rebasing_v1} from
    "script/modules/fundingManager/DeployFM_Rebasing_v1.s.sol";
import {DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "script/modules/fundingManager/DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1.s.sol";
import {DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "script/modules/fundingManager/DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.s.sol";
import {DeployAUT_Role_v1} from
    "script/modules/authorizer/DeployAUT_Role_v1.s.sol";
import {DeployAUT_TokenGated_Role_v1} from
    "script/modules/authorizer/DeployAUT_TokenGated_Role_v1.s.sol";
import {DeployPP_Streaming_v1} from
    "script/modules/paymentProcessor/DeployPP_Streaming_v1.s.sol";
import {DeployLM_PC_RecurringPayments_v1} from
    "script/modules/logicModule/DeployLM_PC_RecurringPayments_v1.s.sol";
import {DeployLM_PC_PaymentRouter_v1} from
    "script/modules/logicModule/DeployLM_PC_PaymentRouter_v1.s.sol";
import {DeployLM_PC_KPIRewarder_v1} from
    "script/modules/logicModule/DeployLM_PC_KPIRewarder.s.sol";
import {DeployAUT_EXT_VotingRoles_v1} from
    "script/modules/authorizer/extensions/DeployAUT_EXT_VotingRoles_v1.s.sol";

// Import external contracts:
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

contract DeploymentScript is Script {
    error BeaconProxyDeploymentFailed();

    // ------------------------------------------------------------------------
    // Instances of Deployer Scripts
    // Orchestrator_v1
    DeployOrchestrator_v1 deployOrchestrator = new DeployOrchestrator_v1();
    // Factories
    DeployModuleFactory_v1 deployModuleFactory = new DeployModuleFactory_v1();
    DeployOrchestratorFactory_v1 deployOrchestratorFactory =
        new DeployOrchestratorFactory_v1();
    // Funding Manager
    DeployFM_Rebasing_v1 deployRebasingFundingManager =
        new DeployFM_Rebasing_v1();
    DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1
        deployBancorVirtualSupplyBondingCurveFundingManager =
            new DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1();
    DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1
        deployRestrictedBancorVirtualSupplyBondingCurveFundingManager =
            new DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1();
    // Authorizer
    DeployAUT_Role_v1 deployRoleAuthorizer = new DeployAUT_Role_v1();
    DeployAUT_TokenGated_Role_v1 deployTokenGatedRoleAuthorizer =
        new DeployAUT_TokenGated_Role_v1();
    // Payment Processor
    DeployPP_Simple_v1 deploySimplePaymentProcessor = new DeployPP_Simple_v1();
    DeployPP_Streaming_v1 deployStreamingPaymentProcessor =
        new DeployPP_Streaming_v1();
    // Logic Module
    DeployLM_PC_Bounties_v1 deployBountyManager = new DeployLM_PC_Bounties_v1();
    DeployLM_PC_RecurringPayments_v1 deployRecurringPaymentManager =
        new DeployLM_PC_RecurringPayments_v1();
    DeployLM_PC_PaymentRouter_v1 deployPaymentRouter =
        new DeployLM_PC_PaymentRouter_v1();
    DeployLM_PC_KPIRewarder_v1 deployKPIRewarder =
        new DeployLM_PC_KPIRewarder_v1();
    // Utils
    DeployAUT_EXT_VotingRoles_v1 deploySingleVoteGovernor =
        new DeployAUT_EXT_VotingRoles_v1();
    // TransactionForwarder_v1
    DeployTransactionForwarder_v1 deployTransactionForwarder =
        new DeployTransactionForwarder_v1();
    // Governor_v1
    DeployGovernor_v1 deployGovernor = new DeployGovernor_v1();
    // FeeManager_v1
    DeployFeeManager_v1 deployFeeManager = new DeployFeeManager_v1();

    // Beacon
    DeployAndSetUpInverterBeacon_v1 deployAndSetupInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();

    // ------------------------------------------------------------------------
    // Deployed Implementation Contracts

    // Orchestrator_v1
    address orchestrator;

    // TransactionForwarder_v1
    address forwarderImplementation;
    address governorImplementation;

    // Funding Manager
    address rebasingFundingManager;
    address bancorBondingCurveFundingManager;
    address restrictedBancorVirtualSupplyBondingCurveFundingManager;
    // Authorizer
    address roleAuthorizer;
    address tokenGatedRoleAuthorizer;
    // Payment Processor
    address simplePaymentProcessor;
    address streamingPaymentProcessor;
    // Logic Module
    address bountyManager;
    address recurringPaymentManager;
    address paymentRouter;
    address kpiRewarder;
    // Utils
    address singleVoteGovernor;

    // ------------------------------------------------------------------------
    // Beacons

    // TransactionForwarder_v1
    address forwarderBeacon;
    // Funding Manager
    address rebasingFundingManagerBeacon;
    address bancorBondingCurveFundingManagerBeacon;
    address restrictedBancorBondingCurveFundingManagerBeacon;
    // Authorizer
    address roleAuthorizerBeacon;
    address tokenGatedRoleAuthorizerBeacon;
    // Payment Processor
    address simplePaymentProcessorBeacon;
    address streamingPaymentProcessorBeacon;
    // Logic Module
    address bountyManagerBeacon;
    address recurringPaymentManagerBeacon;
    address paymentRouterBeacon;
    address kpiRewarderBeacon;
    // Utils
    address singleVoteGovernorBeacon;

    // ------------------------------------------------------------------------
    // Deployed Proxy Contracts

    // These contracts will actually be used at the later point of time

    // Governor_v1
    address governor;

    // FeeManager
    address feeManager;

    // TransactionForwarder_v1
    address forwarder;

    // Factories
    address moduleFactory;
    address orchestratorFactory;

    IModule_v1.Metadata[] initialMetadataRegistration;
    IInverterBeacon_v1[] initialBeaconRegistration;

    // ------------------------------------------------------------------------
    // Module Metadata

    // ------------------------------------------------------------------------
    // Funding Manager

    IModule_v1.Metadata rebasingFundingManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_Rebasing_v1"
    );

    IModule_v1.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
    );

    IModule_v1.Metadata
        restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata =
        IModule_v1.Metadata(
            1,
            0,
            "https://github.com/InverterNetwork/inverter-contracts",
            "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1"
        );

    // ------------------------------------------------------------------------
    // Authorizer

    IModule_v1.Metadata roleAuthorizerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_Roles_v1"
    );

    IModule_v1.Metadata tokenGatedRoleAuthorizerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_TokenGated_Roles_v1"
    );

    // ------------------------------------------------------------------------
    // Payment Processor

    IModule_v1.Metadata simplePaymentProcessorMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Simple_v1"
    );

    IModule_v1.Metadata streamingPaymentProcessorMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Streaming_v1"
    );

    // ------------------------------------------------------------------------
    // Logic Module

    IModule_v1.Metadata recurringPaymentManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_RecurringPayments_v1"
    );

    IModule_v1.Metadata bountyManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_Bounties_v1"
    );

    IModule_v1.Metadata paymentRouterMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_PaymentRouter_v1"
    );

    IModule_v1.Metadata kpiRewarderMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_KPIRewarder_v1"
    );

    // ------------------------------------------------------------------------
    // Utils

    IModule_v1.Metadata singleVoteGovernorMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_EXT_VotingRoles_v1"
    );

    /// @notice Deploys all necessary factories, beacons and implementations
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual returns (address factory) {
        // Fetch the deployer details
        uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Fetch the Multisig addresses
        address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
        address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");

        // Fetch the treasury address
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Governance Contract \n");

        (governor, governorImplementation) =
            deployGovernor.run(communityMultisig, teamMultisig, 1 weeks);

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        console2.log("Fee Manager \n");

        feeManager = deployFeeManager.run(
            address(governor), // owner
            treasury, // treasury
            100, // Collateral Fee 1%
            100 // Issuance Fee 1%
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        console2.log("Deploy orchestrator implementation \n");
        // Orchestrator_v1
        orchestrator = deployOrchestrator.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy forwarder implementation and proxy \n");
        // Deploy TransactionForwarder_v1 implementation
        forwarderImplementation = deployTransactionForwarder.run();

        // Deploy beacon and actual proxy
        (forwarderBeacon, forwarder) = deployAndSetupInverterBeacon_v1
            .deployBeaconAndSetupProxy(
            address(governor), forwarderImplementation, 1, 0
        );

        if (
            forwarder == forwarderImplementation || forwarder == forwarderBeacon
        ) {
            revert BeaconProxyDeploymentFailed();
        }

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy Modules Implementations \n");
        // Deploy implementation contracts.

        // Funding Manager
        rebasingFundingManager = deployRebasingFundingManager.run();
        bancorBondingCurveFundingManager =
            deployBancorVirtualSupplyBondingCurveFundingManager.run();
        restrictedBancorVirtualSupplyBondingCurveFundingManager =
            deployRestrictedBancorVirtualSupplyBondingCurveFundingManager.run();
        // Authorizer
        roleAuthorizer = deployRoleAuthorizer.run();
        tokenGatedRoleAuthorizer = deployTokenGatedRoleAuthorizer.run();
        // Payment Processor
        simplePaymentProcessor = deploySimplePaymentProcessor.run();
        streamingPaymentProcessor = deployStreamingPaymentProcessor.run();
        // Logic Module
        bountyManager = deployBountyManager.run();
        recurringPaymentManager = deployRecurringPaymentManager.run();
        paymentRouter = deployPaymentRouter.run();
        kpiRewarder = deployKPIRewarder.run();
        // Utils
        singleVoteGovernor = deploySingleVoteGovernor.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log(
            "Deploy module beacons and register in module factory v1 \n"
        );
        // Deploy Modules and fill the intitial init list

        // Funding Manager

        initialMetadataRegistration.push(rebasingFundingManagerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    rebasingFundingManager,
                    rebasingFundingManagerMetadata.majorVersion,
                    rebasingFundingManagerMetadata.minorVersion
                )
            )
        );
        initialMetadataRegistration.push(
            bancorVirtualSupplyBondingCurveFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    bancorBondingCurveFundingManager,
                    bancorVirtualSupplyBondingCurveFundingManagerMetadata
                        .majorVersion,
                    bancorVirtualSupplyBondingCurveFundingManagerMetadata
                        .minorVersion
                )
            )
        );
        initialMetadataRegistration.push(
            restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata
        );

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    restrictedBancorVirtualSupplyBondingCurveFundingManager,
                    restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata
                        .majorVersion,
                    restrictedBancorVirtualSupplyBondingCurveFundingManagerMetadata
                        .minorVersion
                )
            )
        );

        // Authorizer
        initialMetadataRegistration.push(roleAuthorizerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    roleAuthorizer,
                    roleAuthorizerMetadata.majorVersion,
                    roleAuthorizerMetadata.minorVersion
                )
            )
        );
        initialMetadataRegistration.push(tokenGatedRoleAuthorizerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    tokenGatedRoleAuthorizer,
                    tokenGatedRoleAuthorizerMetadata.majorVersion,
                    tokenGatedRoleAuthorizerMetadata.minorVersion
                )
            )
        );
        initialMetadataRegistration.push(singleVoteGovernorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    singleVoteGovernor,
                    singleVoteGovernorMetadata.majorVersion,
                    singleVoteGovernorMetadata.minorVersion
                )
            )
        );
        // Payment Processor
        initialMetadataRegistration.push(simplePaymentProcessorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    simplePaymentProcessor,
                    simplePaymentProcessorMetadata.majorVersion,
                    simplePaymentProcessorMetadata.minorVersion
                )
            )
        );
        initialMetadataRegistration.push(streamingPaymentProcessorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    streamingPaymentProcessor,
                    streamingPaymentProcessorMetadata.majorVersion,
                    streamingPaymentProcessorMetadata.minorVersion
                )
            )
        );
        // Logic Module
        initialMetadataRegistration.push(bountyManagerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    bountyManager,
                    bountyManagerMetadata.majorVersion,
                    bountyManagerMetadata.minorVersion
                )
            )
        );
        initialMetadataRegistration.push(recurringPaymentManagerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    recurringPaymentManager,
                    recurringPaymentManagerMetadata.majorVersion,
                    recurringPaymentManagerMetadata.minorVersion
                )
            )
        );
        initialMetadataRegistration.push(kpiRewarderMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    kpiRewarder,
                    kpiRewarderMetadata.majorVersion,
                    kpiRewarderMetadata.minorVersion
                )
            )
        );
        initialMetadataRegistration.push(paymentRouterMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    address(governor),
                    paymentRouter,
                    paymentRouterMetadata.majorVersion,
                    paymentRouterMetadata.minorVersion
                )
            )
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy factory implementations \n");

        // Deploy module factory v1 implementation
        moduleFactory = deployModuleFactory.run(
            address(governor),
            forwarder,
            initialMetadataRegistration,
            initialBeaconRegistration
        );

        // Deploy orchestrator Factory implementation
        orchestratorFactory = deployOrchestratorFactory.run(
            address(governor), orchestrator, moduleFactory, forwarder
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        return (orchestratorFactory);
    }
}
