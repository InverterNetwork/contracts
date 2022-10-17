// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {ProposalFactory} from "src/factories/ProposalFactory.sol";

// Internal Interfaces
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {ModuleFactoryMock} from
    "test/utils/mocks/factories/ModuleFactoryMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

/**
 * Errors library for ProposalFactory's custom errors.
 * Enables checking for errors with vm.expectRevert(Errors.<Error>).
 */
library Errors {
    bytes internal constant ProposalFactory__ModuleDataLengthMismatch =
        abi.encodeWithSignature("ProposalFactory__ModuleDataLengthMismatch()");
}

contract ProposalFactoryTest is Test {
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

    function testDeployment() public {
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

        // Deploy Proposal with id=0
        ProposalMock proposal = ProposalMock(
            factory.createProposal({
                funders: funders,
                authorizerMetadata: IModule.Metadata(1, "Authorizer"),
                authorizerConfigdata: bytes("Authorizer"),
                moduleMetadatas: metadatas,
                moduleConfigdatas: configdatas
            })
        );
        assertEq(proposal.proposalId(), 0);

        // Deploy Proposal with id=1
        proposal = ProposalMock(
            factory.createProposal({
                funders: funders,
                authorizerMetadata: IModule.Metadata(1, "Authorizer"),
                authorizerConfigdata: bytes("Authorizer"),
                moduleMetadatas: metadatas,
                moduleConfigdatas: configdatas
            })
        );
        assertEq(proposal.proposalId(), 1);
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

        vm.expectRevert(Errors.ProposalFactory__ModuleDataLengthMismatch);
        factory.createProposal({
            funders: funders,
            authorizerMetadata: IModule.Metadata(1, "Authorizer"),
            authorizerConfigdata: bytes("Authorizer"),
            moduleMetadatas: metadatas,
            moduleConfigdatas: configdatas
        });
    }
}
