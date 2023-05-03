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

    // Metadata
    IProposalFactory.ProposalConfig proposalConfig = IProposalFactory
        .ProposalConfig({
        owner: address(this),
        token: IERC20(new ERC20Mock("Mock Token", "MOCK"))
    });

    IProposalFactory.ModuleConfig authorizerConfig = IProposalFactory
        .ModuleConfig(
        IModule.Metadata(1, 1, "https://authorizer.com", "Authorizer"),
        bytes("data")
    );

    IProposalFactory.ModuleConfig paymentProcessorConfig = IProposalFactory
        .ModuleConfig(
        IModule.Metadata(
            1, 1, "https://paymentprocessor.com", "SimplePaymentProcessor"
        ),
        bytes("data")
    );

    IProposalFactory.ModuleConfig moduleConfig = IProposalFactory.ModuleConfig(
        IModule.Metadata(1, 1, "https://module.com", "Module"), bytes("")
    );

    function setUp() public {
        moduleFactory = new ModuleFactoryMock();

        target = new Proposal();

        factory = new ProposalFactory(address(target), address(moduleFactory));
    }

    function testValidProposalId(uint getId, uint proposalsCreated) public {
        // Note to stay reasonable
        vm.assume(proposalsCreated < 50);

        for (uint i = 0; i < proposalsCreated; ++i) {
            _deployProposal();
        }
        if (getId > proposalsCreated) {
            vm.expectRevert(
                IProposalFactory.ProposalFactory__InvalidId.selector
            );
        }
        factory.getProposalByID(getId);
    }

    function testDeploymentInvariants() public {
        assertEq(factory.target(), address(target));
        assertEq(factory.moduleFactory(), address(moduleFactory));
    }

    function testCreateProposal(uint modulesLen) public {
        // Note to stay reasonable
        vm.assume(modulesLen < 50);

        // Create optional ModuleConfig instances.
        IProposalFactory.ModuleConfig[] memory moduleConfigs =
        new IProposalFactory.ModuleConfig[](
                modulesLen
            );
        for (uint i; i < modulesLen; ++i) {
            moduleConfigs[i] = moduleConfig;
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
        assertEq(proposal.manager(), address(proposalConfig.owner));

        // Deploy Proposal with id=2
        proposal = factory.createProposal(
            proposalConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );
        // Only check that proposal's id is correct.
        assertEq(proposal.proposalId(), 2);

        //check that proposalFactory idCounter is correct.
        assertEq(factory.getProposalIDCounter(), 2);
    }

    function testProposalMapping(uint proposalAmount) public {
        // Note to stay reasonable
        vm.assume(proposalAmount < 50);

        for (uint i = 1; i < proposalAmount; ++i) {
            address proposal = _deployProposal();
            assertEq(proposal, factory.getProposalByID(i));
        }
    }

    function _deployProposal() private returns (address) {
        //Create Empty ModuleConfig
        IProposalFactory.ModuleConfig[] memory moduleConfigs =
            new IProposalFactory.ModuleConfig[](0);

        // Deploy Proposal
        IProposal proposal = factory.createProposal(
            proposalConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        return address(proposal);
    }
}
