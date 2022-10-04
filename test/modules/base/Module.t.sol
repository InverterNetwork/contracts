// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

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

    bytes internal constant Module__InvalidProposalAddress =
        abi.encodeWithSignature("Module__InvalidProposalAddress()");

    bytes internal constant Module__WantProposalContext =
        abi.encodeWithSignature("Module__WantProposalContext()");
}

contract ModuleTest is Test {
    // SuT
    ModuleMock module;

    // Mocks
    ProposalMock proposal;
    AuthorizerMock authorizer;

    // Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 2;
    string constant GIT_URL = "https://github.com/organization/module";

    IModule.Metadata DATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, GIT_URL);

    function setUp() public {
        authorizer = new AuthorizerMock();
        authorizer.setAllAuthorized(true);

        proposal = new ProposalMock(authorizer);

        module = new ModuleMock();
        module.init(proposal, DATA);

        // Initialize proposal to enable module.
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        proposal.init(modules);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInitialization() public {
        module = new ModuleMock();

        module.init(proposal, DATA);

        assertEq(address(module.proposal()), address(proposal));
    }

    function testInitilizationFailsForInvalidProposal() public {
        module = new ModuleMock();

        vm.expectRevert(Errors.Module__InvalidProposalAddress);
        module.init(IProposal(address(0)), DATA);
    }

    function testInitilizationFailsForNonInitializerFunction() public {
        module = new ModuleMock();

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        module.initNoInitializer(proposal, DATA);
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
