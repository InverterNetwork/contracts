// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

//Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";

import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

// Mocks
import {ModuleV1Mock} from "test/utils/mocks/modules/base/ModuleV1Mock.sol";
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleBaseV1Test is ModuleTest {
    // SuT
    ModuleV1Mock module;

    bytes _CONFIGDATA = bytes("");

    //--------------------------------------------------------------------------
    // Events

    /// @notice Module has been initialized.
    /// @param parentOrchestrator The address of the orchestrator the module is linked to.
    /// @param moduleTitle The title of the module.
    /// @param majorVersion The major version of the module.
    /// @param minorVersion The minor version of the module.
    event ModuleInitialized(
        address indexed parentOrchestrator,
        string indexed moduleTitle,
        uint majorVersion,
        uint minorVersion
    );

    function setUp() public {
        address impl = address(new ModuleV1Mock());
        module = ModuleV1Mock(Clones.clone(impl));

        _setUpOrchestrator(module);

        vm.expectEmit(true, true, true, false);
        emit ModuleInitialized(
            address(_orchestrator), _TITLE, _MAJOR_VERSION, _MINOR_VERSION
        );

        module.init(_orchestrator, _METADATA, _CONFIGDATA);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testSupportsInterface() public {
        assertTrue(module.supportsInterface(type(IModule_v1).interfaceId));
    }

    function testInit() public override {
        // Orchestrator_v1 correctly written to storage.
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
        address impl = address(new ModuleV1Mock());
        module = ModuleV1Mock(Clones.clone(impl));

        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        module.initNoInitializer(_orchestrator, _METADATA, _CONFIGDATA);
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        module.init(_orchestrator, _METADATA, _CONFIGDATA);
    }

    function testInitFailsForInvalidOrchestrator() public {
        address impl = address(new ModuleV1Mock());
        module = ModuleV1Mock(Clones.clone(impl));

        vm.expectRevert(IModule_v1.Module__InvalidOrchestratorAddress.selector);
        module.init(IOrchestrator_v1(address(0)), _METADATA, _CONFIGDATA);
    }

    function testInitFailsIfMetadataInvalid() public {
        address impl = address(new ModuleV1Mock());
        module = ModuleV1Mock(Clones.clone(impl));

        // Invalid if _URL empty.
        vm.expectRevert(IModule_v1.Module__InvalidMetadata.selector);
        module.init(
            _orchestrator,
            IModule_v1.Metadata(_MAJOR_VERSION, _MINOR_VERSION, "", _TITLE),
            _CONFIGDATA
        );

        // Invalid if _TITLE empty.
        vm.expectRevert(IModule_v1.Module__InvalidMetadata.selector);
        module.init(
            _orchestrator,
            IModule_v1.Metadata(_MAJOR_VERSION, _MINOR_VERSION, _URL, ""),
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

    //--------------------------------------------------------------------------
    // ERC2771

    function test_msgSender(address signer, address sender, bool fromForwarder)
        public
    {
        vm.assume(sender != address(_forwarder));

        //Activate the trustedForwarder connection
        _orchestrator.flipConnectToTrustedForwarder();

        //setup function signature that will trigger the _msgSender
        bytes memory originalCallData =
            abi.encodeWithSignature("original_msgSender()");

        //this should add the 20 bytes of the address to the end of the calldata
        bytes memory metaTxCallData = abi.encodePacked(originalCallData, signer);

        if (fromForwarder) {
            sender = address(_forwarder);
        }
        //use call to properly use the added address at the end of the callData
        vm.prank(sender);
        (bool success, bytes memory returndata) =
            address(module).call(metaTxCallData);

        assertTrue(success);

        //Decode the correct perceivedAddress out of the call returndata
        address perceivedSender = abi.decode(returndata, (address));

        if (fromForwarder) {
            //If from Forwarder it should recognize the signer as the sender
            assertEq(perceivedSender, signer);
        } else {
            //If not it should be the sender
            assertEq(perceivedSender, sender);
        }
    }

    function test_msgData(address signer, address sender, bool fromForwarder)
        public
    {
        vm.assume(sender != address(_forwarder));

        //Activate the trustedForwarder connection
        _orchestrator.flipConnectToTrustedForwarder();

        //setup function signature that will trigger the _msgData
        bytes memory originalCallData =
            abi.encodeWithSignature("original_msgData()");

        //this should add the 20 bytes of the address to the end of the calldata
        bytes memory metaTxCallData = abi.encodePacked(originalCallData, signer);

        if (fromForwarder) {
            sender = address(_forwarder);
        }
        //use call to properly use the added address at the end of the callData
        vm.prank(sender);
        (bool success, bytes memory returndata) =
            address(module).call(metaTxCallData);

        assertTrue(success);

        //Decode the correct perceivedData out of the call returndata
        bytes memory perceivedData = abi.decode(returndata, (bytes));

        if (fromForwarder) {
            //If from Forwarder it should have clipped the data to the size before the signer was added
            assertEq(perceivedData, originalCallData);
        } else {
            //If not it should be full data without the clipping
            assertEq(perceivedData, metaTxCallData);
        }
    }
}
