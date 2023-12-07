// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

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

contract baseModuleTest is ModuleTest {
    // SuT
    ModuleMock module;

    bytes _CONFIGDATA = bytes("");

    function setUp() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        _setUpOrchestrator(module);

        _authorizer.setIsAuthorized(address(this), true);

        module.init(_orchestrator, _METADATA, _CONFIGDATA);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testSupportsInterface(bytes4 randomInterface) public {
        bytes4 moduleInterface = type(IModule).interfaceId;
        assertTrue(!module.supportsInterface(randomInterface));
        assertTrue(module.supportsInterface(moduleInterface));
    }

    function testInit() public override {
        // Orchestrator correctly written to storage.
        assertEq(address(module.orchestrator()), address(_orchestrator));

        // Identifier correctly computed.
        assertEq(module.identifier(), LibMetadata.identifier(_METADATA));

        // Version correctly set.
        uint majorVersion;
        uint minorVersion;
        (majorVersion, minorVersion) = module.version();
        assertEq(majorVersion, _MAJOR_VERSION);
        assertEq(minorVersion, _MINOR_VERSION);

        // _URL correctly set.
        assertEq(module.url(), _URL);

        // _TITLE correctly set.
        assertEq(module.title(), _TITLE);
    }

    function testInitFailsForNonInitializerFunction() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        module.initNoInitializer(_orchestrator, _METADATA, _CONFIGDATA);
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        module.init(_orchestrator, _METADATA, _CONFIGDATA);
    }

    function testInitFailsForInvalidOrchestrator() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        vm.expectRevert(IModule.Module__InvalidOrchestratorAddress.selector);
        module.init(IOrchestrator(address(0)), _METADATA, _CONFIGDATA);
    }

    function testInitFailsIfMetadataInvalid() public {
        address impl = address(new ModuleMock());
        module = ModuleMock(Clones.clone(impl));

        // Invalid if _URL empty.
        vm.expectRevert(IModule.Module__InvalidMetadata.selector);
        module.init(
            _orchestrator,
            IModule.Metadata(_MAJOR_VERSION, _MINOR_VERSION, "", _TITLE),
            _CONFIGDATA
        );

        // Invalid if _TITLE empty.
        vm.expectRevert(IModule.Module__InvalidMetadata.selector);
        module.init(
            _orchestrator,
            IModule.Metadata(_MAJOR_VERSION, _MINOR_VERSION, _URL, ""),
            _CONFIGDATA
        );
    }

    //--------------------------------------------------------------------------
    // Role Functions

    function testGrantModuleRole(bytes32 role, address addr) public {
        vm.assume(addr != address(0));

        vm.startPrank(address(this));

        module.grantModuleRole(role, addr);

        bytes32 roleId = _authorizer.generateRoleId(address(module), role);
        bool isAuthorized = _authorizer.checkRoleMembership(roleId, addr);
        assertTrue(isAuthorized);

        vm.stopPrank();
    }

    function testRevokeModuleRole(bytes32 role, address addr) public {
        vm.assume(addr != address(0));

        vm.startPrank(address(this));

        module.grantModuleRole(role, addr);
        module.revokeModuleRole(role, addr);

        bytes32 roleId = _authorizer.generateRoleId(address(module), role);
        bool isAuthorized = _authorizer.checkRoleMembership(roleId, addr);
        assertFalse(isAuthorized);

        vm.stopPrank();
    }
}
