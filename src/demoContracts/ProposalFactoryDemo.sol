// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {
    ProposalFactory,
    IProposalFactory,
    IProposal,
    IModule
} from "src/factories/ProposalFactory.sol";
import {
    IFundingManager,
    IAuthorizer,
    IPaymentProcessor
} from "src/proposal/IProposal.sol";
import {IModuleFactory} from "src/factories/IModuleFactory.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";
import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";
import {MilestoneManager} from "src/modules/logicModule/MilestoneManager.sol";
import {BountyManager} from "src/modules/logicModule/BountyManager.sol";
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";

/**
 * @title Proposal Factory
 *
 * @dev An immutable factory for deploying proposals.
 *
 * @author Inverter Network
 */
contract ProposalFactoryDemo is ProposalFactory {
    bool hasDependency;
    string[] dependencies = new string[](0);

    //rebasingFundingManagerMetadata

    IModule.Metadata rebasingFundingManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/funding-manager",
        "RebasingFundingManager"
    );

    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );
    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory
        .ModuleConfig(
        authorizerMetadata,
        abi.encode(address(this)),
        abi.encode(hasDependency, dependencies)
    );

    // roleAuthorizerMetadata

    IModule.Metadata roleAuthorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/roleAuthorizer", "RoleAuthorizer"
    );

    //paymentProcessorMetadata

    IModule.Metadata paymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "SimplePaymentProcessor"
    );
    IProposalFactory.ModuleConfig paymentProcessorFactoryConfig =
    IProposalFactory.ModuleConfig(
        paymentProcessorMetadata,
        bytes(""),
        abi.encode(hasDependency, dependencies)
    );

    //streamingPaymentProcessorMetadata

    IModule.Metadata streamingPaymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/streaming-payment-processor",
        "StreamingPaymentProcessor"
    );
    IProposalFactory.ModuleConfig streamingPaymentProcessorFactoryConfig =
    IProposalFactory.ModuleConfig(
        streamingPaymentProcessorMetadata,
        bytes(""),
        abi.encode(hasDependency, dependencies)
    );

    //milestoneManagerMetadata

    IModule.Metadata milestoneManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/milestone-manager",
        "MilestoneManager"
    );

    //recurringPaymentManagerMetadata

    IModule.Metadata recurringPaymentManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/recurring-payment-manager",
        "RecurringPaymentManager"
    );
    IProposalFactory.ModuleConfig recurringPaymentManagerFactoryConfig =
    IProposalFactory.ModuleConfig(
        recurringPaymentManagerMetadata,
        abi.encode(1 weeks),
        abi.encode(hasDependency, dependencies)
    );

    // bountyManagerMetadata

    IModule.Metadata bountyManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/bounty-manager", "BountyManager"
    );
    IProposalFactory.ModuleConfig bountyManagerFactoryConfig = IProposalFactory
        .ModuleConfig(
        bountyManagerMetadata, bytes(""), abi.encode(true, dependencies)
    );

    constructor(address target_, address moduleFactory_)
        ProposalFactory(target_, moduleFactory_)
    {}

    function createNewProposalWithMilestoneManagerLogicModule(
        address owner,
        IERC20 token,
        address feeTreasury
    ) external returns (IProposal) {
        IProposalFactory.ProposalConfig memory config =
            IProposalFactory.ProposalConfig(owner, token);

        IProposalFactory.ModuleConfig memory milestoneManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            milestoneManagerMetadata,
            abi.encode(100_000_000, 1_000_000, feeTreasury),
            abi.encode(hasDependency, dependencies)
        );

        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = milestoneManagerFactoryConfig;

        IProposalFactory.ModuleConfig memory rebasingFundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(config.token)),
            abi.encode(false, dependencies)
        );

        IProposalFactory.ModuleConfig memory roleAuthorizerFactoryConfig =
        IProposalFactory.ModuleConfig(
            roleAuthorizerMetadata,
            //Set initial admin role to owner
            abi.encode(owner, owner),
            abi.encode(hasDependency, dependencies)
        );

        return createProposal(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function createNewProposalWithRecurringPaymentManagerLogicModule(
        address owner,
        IERC20 token
    ) external returns (IProposal) {
        IProposalFactory.ProposalConfig memory config =
            IProposalFactory.ProposalConfig(owner, token);

        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = recurringPaymentManagerFactoryConfig;

        IProposalFactory.ModuleConfig memory rebasingFundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(config.token)),
            abi.encode(hasDependency, dependencies)
        );

        IProposalFactory.ModuleConfig memory roleAuthorizerFactoryConfig =
        IProposalFactory.ModuleConfig(
            roleAuthorizerMetadata,
            //Set initial admin role to owner
            abi.encode(owner, owner),
            abi.encode(hasDependency, dependencies)
        );

        return createProposal(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            streamingPaymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function createNewProposalWithBountyManagerLogicModule(
        address owner,
        IERC20 token
    ) external returns (IProposal) {
        IProposalFactory.ProposalConfig memory config =
            IProposalFactory.ProposalConfig(owner, token);

        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = bountyManagerFactoryConfig;

        IProposalFactory.ModuleConfig memory rebasingFundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(config.token)),
            abi.encode(hasDependency, dependencies)
        );

        IProposalFactory.ModuleConfig memory roleAuthorizerFactoryConfig =
        IProposalFactory.ModuleConfig(
            roleAuthorizerMetadata,
            //Set initial admin role to owner
            abi.encode(owner, owner),
            abi.encode(hasDependency, dependencies)
        );

        return createProposal(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }
}
