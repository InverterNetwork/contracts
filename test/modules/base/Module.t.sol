// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";

import {Orchestrator} from "src/orchestrator/Orchestrator.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleTest is Test {
    // SuT
    ModuleMock module;

    Orchestrator orchestrator;

    // Mocks
    FundingManagerMock fundingManager;
    AuthorizerMock authorizer;
    PaymentProcessorMock paymentProcessor;

    // Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Payment Processor";

    IModule.Metadata METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    bytes CONFIGDATA = bytes("");

    function setUp() public {
        fundingManager = new FundingManagerMock();

        authorizer = new AuthorizerMock();
        authorizer.setAllAuthorized(true);

        paymentProcessor = new PaymentProcessorMock();

        address orchestratorImpl = address(new Orchestrator());
        orchestrator = Orchestrator(Clones.clone(orchestratorImpl));

        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        module.init(orchestrator, METADATA, CONFIGDATA);

        // Initialize orchestrator to enable module.
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        orchestrator.init(
            1,
            address(this),
            IERC20(new ERC20Mock("Mock", "MOCK")),
            modules,
            fundingManager,
            authorizer,
            paymentProcessor
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        // Orchestrator correctly written to storage.
        assertEq(address(module.orchestrator()), address(orchestrator));

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
        module.initNoInitializer(orchestrator, METADATA, CONFIGDATA);
    }

    function testReinitFails() public {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        module.init(orchestrator, METADATA, CONFIGDATA);
    }

    function testInitFailsForInvalidOrchestrator() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        vm.expectRevert(IModule.Module__InvalidOrchestratorAddress.selector);
        module.init(IOrchestrator(address(0)), METADATA, CONFIGDATA);
    }

    function testInitFailsIfMetadataInvalid() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        // Invalid if url empty.
        vm.expectRevert(IModule.Module__InvalidMetadata.selector);
        module.init(
            orchestrator,
            IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, "", TITLE),
            CONFIGDATA
        );

        // Invalid if title empty.
        vm.expectRevert(IModule.Module__InvalidMetadata.selector);
        module.init(
            orchestrator,
            IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, ""),
            CONFIGDATA
        );
    }
}
