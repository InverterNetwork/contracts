// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

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

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {ModuleFactoryMock} from
    "test/utils/mocks/factories/ModuleFactoryMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ProposalFactoryTest is Test {
    // SuT
    ProposalFactory factory;

    // Mocks
    AuthorizerMock authorizer;
    ProposalMock target;
    ModuleFactoryMock moduleFactory;

    function setUp() public {
        authorizer = new AuthorizerMock();

        target = new ProposalMock(authorizer);
        moduleFactory = new ModuleFactoryMock();

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
            .ProposalConfig(IERC20(new ERC20Mock("Test Token", "TEST")));

        // Create {IAuthorizer} ModuleConfig instance.
        IProposalFactory.ModuleConfig memory authorizerConfig = IProposalFactory
            .ModuleConfig(IModule.Metadata(1, "Authorizer"), bytes("Authorizer"));

        // Create {IPaymentProcessor} ModuleConfig instance.
        IProposalFactory.ModuleConfig memory paymentProcessorConfig =
        IProposalFactory.ModuleConfig(
            IModule.Metadata(1, "PaymentProcessor"), bytes("PaymentProcessor")
        );

        // Create optional ModuleConfig instances.
        IProposalFactory.ModuleConfig[] memory moduleConfigs =
            new IProposalFactory.ModuleConfig[](modulesLen);
        for (uint i; i < modulesLen; i++) {
            moduleConfigs[i].metadata = IModule.Metadata(1, "");
            moduleConfigs[i].configdata = bytes("");
        }

        // Deploy Proposal with id=1
        IProposal proposal = factory.createProposal(
            proposalConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );
        assertEq(proposal.proposalId(), 1);

        // Deploy Proposal with id=2
        proposal = factory.createProposal(
            proposalConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );
        assertEq(proposal.proposalId(), 2);
    }
}
