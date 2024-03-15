// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Import interfaces:

import {IModule} from "src/modules/base/IModule.sol";
import {IModuleFactory} from "src/factories/ModuleFactory.sol";

// Import scripts:

import {DeployAndSetUpBeacon} from "script/proxies/DeployAndSetUpBeacon.s.sol";
import {DeployModuleFactory} from "script/factories/DeployModuleFactory.s.sol";
import {DeployOrchestratorFactory} from
    "script/factories/DeployOrchestratorFactory.s.sol";
import {DeployBountyManager} from "script/modules/DeployBountyManager.s.sol";

import {DeployTransactionForwarder} from
    "script/external/DeployTransactionForwarder.s.sol";
import {DeployOrchestrator} from "script/orchestrator/DeployOrchestrator.s.sol";
import {DeploySimplePaymentProcessor} from
    "script/modules/paymentProcessor/DeploySimplePaymentProcessor.s.sol";
import {DeployRebasingFundingManager} from
    "script/modules/fundingManager/DeployRebasingFundingManager.s.sol";
import {DeployRoleAuthorizer} from
    "script/modules/governance/DeployRoleAuthorizer.s.sol";

//@todo all the dependencies are missing of the scripts i added

contract DeploymentScript is Script {
    // ------------------------------------------------------------------------
    // Instances of Deployer Scripts
    //Orchestrator
    DeployOrchestrator deployOrchestrator = new DeployOrchestrator();
    // Factories
    DeployModuleFactory deployModuleFactory = new DeployModuleFactory();
    DeployOrchestratorFactory deployOrchestratorFactory =
        new DeployOrchestratorFactory();
    // Funding Manager
    DeployRebasingFundingManager deployRebasingFundingManager =
        new DeployRebasingFundingManager();
    DeployBancorVirtualSupplyBondingCurveFundingManager
        deployBancorVirtualSupplyBondingCurveFundingManager =
            new DeployBancorVirtualSupplyBondingCurveFundingManager();
    // Authorizer
    DeployRoleAuthorizer deployRoleAuthorizer = new DeployRoleAuthorizer();
    DeployTokenGatedRoleAuthorizer deployTokenGatedRoleAuthorizer =
        new DeployTokenGatedRoleAuthorizer();
    // Payment Processor
    DeploySimplePaymentProcessor deploySimplePaymentProcessor =
        new DeploySimplePaymentProcessor();
    DeployStreamingPaymentProcessor deployStreamingPaymentProcessor =
        new DeployStreamingPaymentProcessor();
    // Logic Module
    DeployBountyManager deployBountyManager = new DeployBountyManager();
    DeployRecurringPaymentManager deployRecurringPaymentManager =
        new DeployRecurringPaymentManager();
    // Utils
    DeploySingleVoteGovernor deploySingleVoteGovernor =
        new DeploySingleVoteGovernor();
    //@todo Metadatamanager needs to be added as a script

    // TransactionForwarder
    DeployTransactionForwarder deployTransactionForwarder =
        new DeployTransactionForwarder();

    //Beacon
    DeployAndSetUpBeacon deployAndSetUpBeacon = new DeployAndSetUpBeacon();

    // ------------------------------------------------------------------------
    // Deployed Implementation Contracts

    //Orchestrator
    address orchestrator;

    //TransactionForwarder
    address forwarderImplementation;

    // Factories
    address moduleFactoryImplementation;
    address orchestratorFactoryImplementation;

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

    //TransactionForwarder
    address forwarderBeacon;
    // Factories
    address moduleFactoryBeacon;
    address orchestratorFactoryBeacon;
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

    //TransactionForwarder
    address forwarder;

    // Factories
    address moduleFactory;
    address orchestratorFactory;

    // ------------------------------------------------------------------------
    // Module Metadata

    // ------------------------------------------------------------------------
    // Funding Manager

    IModule.Metadata rebasingFundingManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/funding-manager",
        "RebasingFundingManager"
    );

    IModule.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/bonding-curve-funding-manager",
        "BancorVirtualSupplyBondingCurveFundingManager"
    );

    // ------------------------------------------------------------------------
    // Authorizer

    IModule.Metadata roleAuthorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/roleAuthorizer", "RoleAuthorizer"
    );

    IModule.Metadata tokenRoleAuthorizerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/tokenRoleAuthorizer",
        "TokenGatedRoleAuthorizer"
    );

    // ------------------------------------------------------------------------
    // Payment Processor

    IModule.Metadata simplePaymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "SimplePaymentProcessor"
    );

    IModule.Metadata streamingPaymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/streaming-payment-processor",
        "StreamingPaymentProcessor"
    );

    // ------------------------------------------------------------------------
    // Logic Module

    IModule.Metadata recurringPaymentManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/recurring-payment-manager",
        "RecurringPaymentManager"
    );

    IModule.Metadata bountyManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/bounty-manager", "BountyManager"
    );

    // ------------------------------------------------------------------------
    // Utils

    IModule.Metadata singleVoteGovernorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/single-vote-governor",
        "SingleVoteGovernor"
    );

    IModule.Metadata metadataManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/metadata-manager", "MetadataManager"
    );

    /// @notice Deploys all necessary factories, beacons and implementations
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual returns (address factory) {
        // Deploy implementation contracts.
        //Orchestrator
        orchestrator = deployOrchestrator.run();

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

        //@todo Check if the references are actually leading to the proxies and not the implementations (The proxies should be used and not the implementations (The beacon just points to the implementation))

        //Deploy TransactionForwarder implementation
        forwarderImplementation = deployTransactionForwarder.run();

        //Deploy beacon and actual proxy
        (forwarderBeacon, forwarder) = deployAndSetUpBeacon
            .deployBeaconAndSetupProxy(forwarderImplementation, 1, 1);

        //Deploy module Factory implementation
        moduleFactoryImplementation = deployModuleFactory.run(forwarder);

        //Deploy beacon and actual proxy
        moduleFactoryBeacon;

        (moduleFactoryBeacon, moduleFactory) = deployAndSetUpBeacon
            .deployBeaconAndSetupProxy(moduleFactoryImplementation, 1, 1);

        //Deploy orchestrator Factory implementation
        orchestratorFactoryImplementation = deployOrchestratorFactory.run(
            orchestrator, moduleFactory, forwarder
        );

        //Deploy beacon and actual proxy
        (orchestratorFactoryBeacon, orchestratorFactory) = deployAndSetUpBeacon
            .deployBeaconAndSetupProxy(orchestratorFactoryImplementation, 1, 1);

        //Deploy Modules and Register in factories

        // Funding Manager
        rebasingFundingManagerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            rebasingFundingManager,
            moduleFactory,
            rebasingFundingManagerMetadata
        );
        bancorBondingCurveFundingManagerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            bancorBondingCurveFundingManager,
            moduleFactory,
            bancorBondingCurveFundingManagerMetadata
        );
        // Authorizer
        roleAuthorizerBeacon = deployAndSetUpBeacon.deployAndRegisterInFactory(
            roleAuthorizer, moduleFactory, roleAuthorizerMetadata
        );
        tokenGatedRoleAuthorizerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            tokenGatedRoleAuthorizer,
            moduleFactory,
            tokenGatedRoleAuthorizerMetadata
        );
        // Payment Processor
        simplePaymentProcessorBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            simplePaymentProcessor,
            moduleFactory,
            simplePaymentProcessorMetadata
        );
        streamingPaymentProcessorBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            streamingPaymentProcessor,
            moduleFactory,
            streamingPaymentProcessorMetadata
        );
        // Logic Module
        bountyManagerBeacon = deployAndSetUpBeacon.deployAndRegisterInFactory(
            bountyManager, moduleFactory, bountyManagerMetadata
        );
        recurringPaymentManagerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            recurringPaymentManager,
            moduleFactory,
            recurringPaymentManagerMetadata
        );

        // Utils
        singleVoteGovernorBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            singleVoteGovernor, moduleFactory, singleVoteGovernor
        );
        metadataManagerBeacon = deployAndSetUpBeacon.deployAndRegisterInFactory(
            metadataManager, moduleFactory, metadataManagerMetadata
        );

        //@todo check that it actually runs

        return (orchestratorFactory);
    }
}
