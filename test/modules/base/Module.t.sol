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

    bytes internal constant Module__InvalidVersionPair =
        abi.encodeWithSignature("Module__InvalidVersionPair()");

    bytes internal constant Module__InvalidGitURL =
        abi.encodeWithSignature("Module__InvalidGitURL()");

    bytes internal constant Module__InvalidMinorVersion =
        abi.encodeWithSignature("Module__InvalidMinorVersion()");
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

    function testInit() public {
        module = new ModuleMock();

        module.init(proposal, DATA);

        assertEq(address(module.proposal()), address(proposal));
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

    function testInitFailsForInvalidVersionPair() public {
        module = new ModuleMock();

        // Invalid: Version v0.0.
        DATA = IModule.Metadata(0, 0, GIT_URL);

        vm.expectRevert(Errors.Module__InvalidVersionPair);
        module.init(proposal, DATA);
    }

    function testInitFailsForInvalidGitURL() public {
        module = new ModuleMock();

        // Invalid: Empty git url
        DATA = IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, "");

        vm.expectRevert(Errors.Module__InvalidGitURL);
        module.init(proposal, DATA);
    }

    //--------------------------------------------------------------------------
    // Tests: Increase Minor Version

    function testIncreaseMinorVersion(uint newMinorVersion) public {
        // @todo Test Module::increaseMinorVersion()
        // @todo Test Module::identifier()
        // @todo Make _triggerCallback functions fail if call failed?
    }

    function testIncreaseMinorVersionIsAuthenticated()
        public
    {
        authorizer.setAllAuthorized(false);

        vm.expectRevert(Errors.Module__CallerNotAuthorized);
        module.increaseMinorVersion(MINOR_VERSION + 1);
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
