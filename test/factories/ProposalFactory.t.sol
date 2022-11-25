// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Internal Dependencies
import {ProposalFactory} from "src/factories/ProposalFactory.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {
    IProposalFactory,
    IModule,
    IProposal
} from "src/factories/IProposalFactory.sol";

import {Proposal} from "src/proposal/Proposal.sol";

// Mocks
import {ModuleFactoryMock} from
    "test/utils/mocks/factories/ModuleFactoryMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ProposalFactoryTest is Test {
    // SuT
    ProposalFactory factory;

    Proposal target;

    // Mocks
    ModuleFactoryMock moduleFactory;

    function setUp() public {
        moduleFactory = new ModuleFactoryMock();

        target = new Proposal();

        factory = new ProposalFactory(address(target), address(moduleFactory));
    }

    function testDeploymentInvariants() public {
        assertEq(factory.target(), address(target));
        assertEq(factory.moduleFactory(), address(moduleFactory));
    }

    function testCreateProposal(uint modulesLen) public {
        // Note to stay reasonable
        vm.assume(modulesLen < 50);

        // Create ProposalConfig instance.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({
            owner: address(this),
            token: IERC20(new ERC20Mock("Mock Token", "MOCK"))
        });

        // Create {IAuthorizer} ModuleConfig instance.
        IProposalFactory.ModuleConfig memory authorizerConfig = IProposalFactory
            .ModuleConfig(
            IModule.Metadata(1, 1, "https://authorizer.com", "Authorizer"),
            bytes("data")
        );

        // Create {IPaymentProcessor} ModuleConfig instance.
        IProposalFactory.ModuleConfig memory paymentProcessorConfig =
        IProposalFactory.ModuleConfig(
            IModule.Metadata(
                1, 1, "https://paymentprocessor.com", "PaymentProcessor"
            ),
            bytes("data")
        );

        // Create optional ModuleConfig instances.
        IProposalFactory.ModuleConfig[] memory moduleConfigs =
            new IProposalFactory.ModuleConfig[](modulesLen);
        for (uint i; i < modulesLen; i++) {
            moduleConfigs[i].metadata =
                IModule.Metadata(1, 1, "https://module.com", "Module");
            moduleConfigs[i].configdata = bytes("");
        }

        // Deploy Proposal with id=1
        IProposal proposal = factory.createProposal(
            proposalConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        // Check that proposal's strorage correctly initialized.
        assertEq(proposal.proposalId(), 1);
        assertEq(address(proposal.token()), address(proposalConfig.token));
        assertTrue(address(proposal.authorizer()) != address(0));
        assertTrue(address(proposal.paymentProcessor()) != address(0));

        // Check that other proposal's dependencies correctly initialized.
        // Ownable:
        assertEq(proposal.owner(), address(proposalConfig.owner));

        // Deploy Proposal with id=2
        proposal = factory.createProposal(
            proposalConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );
        // Only check that proposal's id is correct.
        assertEq(proposal.proposalId(), 2);
    }
}
