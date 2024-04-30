// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Import interfaces:

import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";

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
import {DeployAUT_Role_v1} from
    "script/modules/governance/DeployAUT_Role_v1.s.sol";
import {DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "script/modules/fundingManager/DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1.s.sol";
import {DeployAUT_TokenGated_Role_v1} from
    "script/modules/governance/DeployAUT_TokenGated_Role_v1.s.sol";
import {DeployPP_Streaming_v1} from
    "script/modules/paymentProcessor/DeployPP_Streaming_v1.s.sol";
import {DeployLM_PC_RecurringPayments_v1} from
    "script/modules/logicModule/DeployLM_PC_RecurringPayments_v1.s.sol";
import {DeployVotingRoleManager_v1} from
    "script/modules/utils/DeployVotingRoleManager_v1.s.sol";
import {DeployMetadataManager} from "script/utils/DeployMetadataManager.s.sol";

contract DeploymentScript is Script {
    error BeaconProxyDeploymentFailed();

    // ------------------------------------------------------------------------
    // Instances of Deployer Scripts
    //Orchestrator_v1
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
    // Utils
    DeployVotingRoleManager_v1 deploySingleVoteGovernor =
        new DeployVotingRoleManager_v1();
    DeployMetadataManager deployMetadataManager = new DeployMetadataManager();
    // TransactionForwarder_v1
    DeployTransactionForwarder_v1 deployTransactionForwarder =
        new DeployTransactionForwarder_v1();
    //Governor_v1
    DeployGovernor_v1 deployGovernor = new DeployGovernor_v1();
    //FeeManager_v1
    DeployFeeManager_v1 deployFeeManager = new DeployFeeManager_v1();

    //Beacon
    DeployAndSetUpInverterBeacon_v1 deployAndSetupInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();

    // ------------------------------------------------------------------------
    // Deployed Implementation Contracts

    //Orchestrator_v1
    address orchestrator;

    //TransactionForwarder_v1
    address forwarderImplementation;
    address governorImplementation;

    // Funding Manager
    address rebasingFundingManager;
    address bancorBondingCurveFundingManager;
    // Authorizer
    address roleAuthorizer;
    address tokenGatedRoleAuthorizer;
    // Payment Processor
    address simplePaymentProcessor;
    address streamingPaymentProcessor;
    // Logic Module
    address bountyManager;
    address recurringPaymentManager;
    // Utils
    address singleVoteGovernor;
    address metadataManager;

    // ------------------------------------------------------------------------
    // Beacons

    //TransactionForwarder_v1
    address forwarderBeacon;
    // Funding Manager
    address rebasingFundingManagerBeacon;
    address bancorBondingCurveFundingManagerBeacon;
    // Authorizer
    address roleAuthorizerBeacon;
    address tokenGatedRoleAuthorizerBeacon;
    // Payment Processor
    address simplePaymentProcessorBeacon;
    address streamingPaymentProcessorBeacon;
    // Logic Module
    address bountyManagerBeacon;
    address recurringPaymentManagerBeacon;
    // Utils
    address singleVoteGovernorBeacon;
    address metadataManagerBeacon;

    // ------------------------------------------------------------------------
    // Deployed Proxy Contracts

    //These contracts will actually be used at the later point of time

    //Governor_v1
    address governor;

    //FeeManager
    address feeManager;

    //TransactionForwarder_v1
    address forwarder;

    // Factories
    address moduleFactory;
    address orchestratorFactory;

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

    // ------------------------------------------------------------------------
    // Utils

    IModule_v1.Metadata singleVoteGovernorMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "VotingRoleManager_v1"
    );

    IModule_v1.Metadata metadataManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "MetadataManager_v1"
    );

    /// @notice Deploys all necessary factories, beacons and implementations
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual returns (address factory) {
        //Fetch the deployer address
        address deployer = vm.addr(vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY"));

        //Fetch the Multisig addresses
        address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
        address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");

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
            address(governor), //owner
            communityMultisig, //@note This is not the real target is it?
            100, //Collateral Fee 1%
            100 //Issuance Fee 1%
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        console2.log("Deploy orchestrator implementation \n");
        //Orchestrator_v1
        orchestrator = deployOrchestrator.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy forwarder implementation and proxy \n");
        //Deploy TransactionForwarder_v1 implementation
        forwarderImplementation = deployTransactionForwarder.run();

        //Deploy beacon and actual proxy
        (forwarderBeacon, forwarder) = deployAndSetupInverterBeacon_v1
            .deployBeaconAndSetupProxy(deployer, forwarderImplementation, 1, 0);

        if (
            forwarder == forwarderImplementation || forwarder == forwarderBeacon
        ) {
            revert BeaconProxyDeploymentFailed();
        }

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy factory implementations \n");

        //Deploy module factory v1 implementation
        moduleFactory = deployModuleFactory.run(address(governor), forwarder);

        //Deploy orchestrator Factory implementation
        orchestratorFactory = deployOrchestratorFactory.run(
            orchestrator, moduleFactory, forwarder
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy Modules Implementations \n");
        // Deploy implementation contracts.

        // Funding Manager
        rebasingFundingManager = deployRebasingFundingManager.run();
        bancorBondingCurveFundingManager =
            deployBancorVirtualSupplyBondingCurveFundingManager.run();
        // Authorizer
        roleAuthorizer = deployRoleAuthorizer.run();
        tokenGatedRoleAuthorizer = deployTokenGatedRoleAuthorizer.run();
        // Payment Processor
        simplePaymentProcessor = deploySimplePaymentProcessor.run();
        streamingPaymentProcessor = deployStreamingPaymentProcessor.run();
        // Logic Module
        bountyManager = deployBountyManager.run();
        recurringPaymentManager = deployRecurringPaymentManager.run();
        // Utils
        singleVoteGovernor = deploySingleVoteGovernor.run();
        metadataManager = deployMetadataManager.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log(
            "Deploy module beacons and register in module factory v1 \n"
        );
        //Deploy Modules and Register in factories

        // Funding Manager
        rebasingFundingManagerBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            rebasingFundingManager,
            moduleFactory,
            rebasingFundingManagerMetadata
        );
        bancorBondingCurveFundingManagerBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            bancorBondingCurveFundingManager,
            moduleFactory,
            bancorVirtualSupplyBondingCurveFundingManagerMetadata
        );
        // Authorizer
        roleAuthorizerBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            roleAuthorizer,
            moduleFactory,
            roleAuthorizerMetadata
        );
        tokenGatedRoleAuthorizerBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            tokenGatedRoleAuthorizer,
            moduleFactory,
            tokenGatedRoleAuthorizerMetadata
        );
        // Payment Processor
        simplePaymentProcessorBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            simplePaymentProcessor,
            moduleFactory,
            simplePaymentProcessorMetadata
        );
        streamingPaymentProcessorBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            streamingPaymentProcessor,
            moduleFactory,
            streamingPaymentProcessorMetadata
        );
        // Logic Module
        bountyManagerBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            bountyManager,
            moduleFactory,
            bountyManagerMetadata
        );
        recurringPaymentManagerBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            recurringPaymentManager,
            moduleFactory,
            recurringPaymentManagerMetadata
        );

        // Utils
        singleVoteGovernorBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            singleVoteGovernor,
            moduleFactory,
            singleVoteGovernorMetadata
        );
        metadataManagerBeacon = deployAndSetupInverterBeacon_v1
            .deployAndRegisterInFactory(
            address(governor),
            metadataManager,
            moduleFactory,
            metadataManagerMetadata
        );

        return (orchestratorFactory);
    }
}
