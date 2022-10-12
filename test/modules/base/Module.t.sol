// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Libraries
import {MetadataLib} from "src/modules/lib/MetadataLib.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {PayerMock} from "test/utils/mocks/PayerMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

/**
 * Errors library for Module's custom errors.
 * Enables checking for errors with vm.expectRevert(Errors.<Error>).
 */
library Errors {
    bytes internal constant Module__CallerNotAuthorized =
        abi.encodeWithSignature("Module__CallerNotAuthorized()");

    bytes internal constant Module__OnlyCallableByProposal =
        abi.encodeWithSignature("Module__OnlyCallableByProposal()");

    bytes internal constant Module__WantProposalContext =
        abi.encodeWithSignature("Module__WantProposalContext()");

    bytes internal constant Module__InvalidProposalAddress =
        abi.encodeWithSignature("Module__InvalidProposalAddress()");

    bytes internal constant Module__InvalidMetadata =
        abi.encodeWithSignature("Module__InvalidMetadata()");
}

contract ModuleTest is Test {
    // SuT
    ModuleMock module;

    // Mocks
    ProposalMock proposal;
    AuthorizerMock authorizer;
    PayerMock payer;

    // Constants
    uint constant MAJOR_VERSION = 1;
    string constant GIT_URL = "https://github.com/organization/module";

    IModule.Metadata DATA = IModule.Metadata(MAJOR_VERSION, GIT_URL);

    function setUp() public {
        authorizer = new AuthorizerMock();
        authorizer.setAllAuthorized(true);

        payer = new PayerMock();

        proposal = new ProposalMock();

        module = new ModuleMock();
        module.init(proposal, DATA);

        // Initialize proposal to enable module.
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        proposal.init(authorizer, payer, modules);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        module = new ModuleMock();

        module.init(proposal, DATA);

        // Proposal correctly written to storage.
        assertEq(address(module.proposal()), address(proposal));

        // Metadata correctly written to storage.
        bytes32 got = MetadataLib.identifier(module.info());
        bytes32 want = MetadataLib.identifier(DATA);
        assertEq(got, want);

        // Module's identifier correctly computed.
        got = module.identifier();
        want = MetadataLib.identifier(DATA);
        assertEq(got, want);
    }

    function testInitFailsForInvalidProposal() public {
        module = new ModuleMock();

        vm.expectRevert(Errors.Module__InvalidProposalAddress);
        module.init(IProposal(address(0)), DATA);
    }

    function testInitFailsForNonInitializerFunction() public {
        module = new ModuleMock();

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        module.initNoInitializer(proposal, DATA);
    }

    function testInitFailsIfMetadataInvalid(uint majorVersion) public {
        module = new ModuleMock();

        // Invalid if gitURL empty.
        IModule.Metadata memory data = IModule.Metadata(majorVersion, "");

        vm.expectRevert(Errors.Module__InvalidMetadata);
        module.init(proposal, data);
    }

    //--------------------------------------------------------------------------
    // Tests: (Un)Pause Functionality

    function testPause() public {
        module.pause();
        assertTrue(module.paused());
    }

    function testUnpause() public {
        module.pause();
        module.unpause();
        assertTrue(!module.paused());
    }

    function testPauseIsAuthenticated() public {
        authorizer.setAllAuthorized(false);

        vm.expectRevert(Errors.Module__CallerNotAuthorized);
        module.pause();
    }

    function testUnpauseIsAuthenticated() public {
        authorizer.setAllAuthorized(false);

        vm.expectRevert(Errors.Module__CallerNotAuthorized);
        module.unpause();
    }
}
