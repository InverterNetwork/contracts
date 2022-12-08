// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";

import {Proposal} from "src/proposal/Proposal.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleTest is Test {
    // SuT
    ModuleMock module;

    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;

    // Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Payment Processor";

    IModule.Metadata METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    bytes CONFIGDATA = bytes("");

    function setUp() public {
        authorizer = new AuthorizerMock();
        authorizer.setAllAuthorized(true);

        address proposalImpl = address(new Proposal());
        proposal = Proposal(Clones.clone(proposalImpl));

        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        module.init(proposal, METADATA, CONFIGDATA);

        // Initialize proposal to enable module.
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        proposal.init(
            1,
            address(this),
            IERC20(new ERC20Mock("Mock", "MOCK")),
            modules,
            authorizer,
            new PaymentProcessorMock()
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        // Proposal correctly written to storage.
        assertEq(address(module.proposal()), address(proposal));

        // Identifier correctly computed.
        assertEq(module.identifier(), LibMetadata.identifier(METADATA));

        // Version correctly set.
        uint majorVersion;
        uint minorVersion;
        (majorVersion, minorVersion) = module.version();
        assertEq(majorVersion, MAJOR_VERSION);
        assertEq(minorVersion, MINOR_VERSION);

        // URL correctly set.
        assertEq(module.url(), URL);

        // Title correctly set.
        assertEq(module.title(), TITLE);
    }

    function testInitFailsForNonInitializerFunction() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        module.initNoInitializer(proposal, METADATA, CONFIGDATA);
    }

    function testReinitFails() public {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        module.init(proposal, METADATA, CONFIGDATA);
    }

    function testInitFailsForInvalidProposal() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        vm.expectRevert(IModule.Module__InvalidProposalAddress.selector);
        module.init(IProposal(address(0)), METADATA, CONFIGDATA);
    }

    function testInitFailsIfMetadataInvalid() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        // Invalid if url empty.
        vm.expectRevert(IModule.Module__InvalidMetadata.selector);
        module.init(
            proposal,
            IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, "", TITLE),
            CONFIGDATA
        );

        // Invalid if title empty.
        vm.expectRevert(IModule.Module__InvalidMetadata.selector);
        module.init(
            proposal,
            IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, ""),
            CONFIGDATA
        );
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

    function testPauseIsAuthenticated(address caller) public {
        vm.assume(caller != proposal.owner());
        authorizer.setAllAuthorized(false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        module.pause();
    }

    function testUnpauseIsAuthenticated(address caller) public {
        vm.assume(caller != proposal.owner());
        authorizer.setAllAuthorized(false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        module.unpause();
    }
}
