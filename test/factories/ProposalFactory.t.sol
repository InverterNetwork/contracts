// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {ProposalFactory} from "src/factories/ProposalFactory.sol";

// Internal Interfaces
import {IProposalFactory} from "src/interfaces/IProposalFactory.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

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

    function testCreateProposal(address[] memory funders, uint modulesLen)
        public
    {
        // Note to stay reasonable
        vm.assume(funders.length < 50);
        vm.assume(modulesLen < 50);

        // Create modules metadata and configdata arrays.
        IModule.Metadata[] memory metadatas = new IModule.Metadata[](modulesLen);
        bytes[] memory configdatas = new bytes[](modulesLen);
        for (uint i; i < modulesLen; i++) {
            metadatas[i] = IModule.Metadata(1, "");
            configdatas[i] = bytes("");
        }

        // Create a mock payment Token
        ERC20Mock paymentToken = new ERC20Mock("TestToken", "TST");

        // Deploy Proposal with id=1
        ProposalMock proposal = ProposalMock(
            factory.createProposal({
                funders: funders,
                authorizerMetadata: IModule.Metadata(1, "Authorizer"),
                authorizerConfigdata: bytes("Authorizer"),
                paymentProcessorMetadata: IModule.Metadata(1, "PaymentProcessor"),
                paymentProcessorConfigdata: bytes("PaymentProcessor"),
                paymentToken: address(paymentToken),
                moduleMetadatas: metadatas,
                moduleConfigdatas: configdatas
            })
        );
        assertEq(proposal.proposalId(), 1);

        // Deploy Proposal with id=2
        proposal = ProposalMock(
            factory.createProposal({
                funders: funders,
                authorizerMetadata: IModule.Metadata(1, "Authorizer"),
                authorizerConfigdata: bytes("Authorizer"),
                paymentProcessorMetadata: IModule.Metadata(1, "PaymentProcessor"),
                paymentProcessorConfigdata: bytes("PaymentProcessor"),
                paymentToken: address(paymentToken),
                moduleMetadatas: metadatas,
                moduleConfigdatas: configdatas
            })
        );
        assertEq(proposal.proposalId(), 2);
    }

    function testCreateProposalFailsIfModuleDataLengthMismatch(
        address[] memory funders,
        uint modulesLen
    ) public {
        // Note to stay reasonable.
        vm.assume(funders.length < 50);
        vm.assume(modulesLen < 50);

        // Create modules metadata and configdata arrays.
        // Note to add one more element to configdata.
        IModule.Metadata[] memory metadatas = new IModule.Metadata[](modulesLen);
        bytes[] memory configdatas = new bytes[](modulesLen + 1);
        for (uint i; i < modulesLen; i++) {
            metadatas[i] = IModule.Metadata(1, "");
            configdatas[i] = bytes("");
        }
        configdatas[modulesLen] = bytes("");

        // Create a mock payment Token
        ERC20Mock paymentToken = new ERC20Mock("TestToken", "TST");

        vm.expectRevert(
            IProposalFactory.ProposalFactory__ModuleDataLengthMismatch.selector
        );
        factory.createProposal({
            funders: funders,
            authorizerMetadata: IModule.Metadata(1, "Authorizer"),
            authorizerConfigdata: bytes("Authorizer"),
            paymentProcessorMetadata: IModule.Metadata(1, "PaymentProcessor"),
            paymentProcessorConfigdata: bytes("PaymentProcessor"),
            paymentToken: address(paymentToken),
            moduleMetadatas: metadatas,
            moduleConfigdatas: configdatas
        });
    }
}
