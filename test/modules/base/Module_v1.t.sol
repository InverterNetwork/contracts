// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// Internal Dependencies
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
import {FundingManagerV1Mock} from
    "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "test/utils/mocks/modules/PaymentProcessorV1Mock.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
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
    /// @param  parentOrchestrator The address of the orchestrator the module is linked to.
    /// @param  metadata The metadata of the module.
    event ModuleInitialized(
        address indexed parentOrchestrator, IModule_v1.Metadata metadata
    );

    function setUp() public {
        address impl = address(new ModuleV1Mock());
        module = ModuleV1Mock(Clones.clone(impl));

        _setUpOrchestrator(module);

        vm.expectEmit(true, true, true, false);
        emit ModuleInitialized(address(_orchestrator), _METADATA);

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
        uint patchVersion;
        (majorVersion, minorVersion, patchVersion) = module.version();
        assertEq(majorVersion, _MAJOR_VERSION);
        assertEq(minorVersion, _MINOR_VERSION);
        assertEq(patchVersion, _PATCH_VERSION);

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
            IModule_v1.Metadata(
                _MAJOR_VERSION, _MINOR_VERSION, _PATCH_VERSION, "", _TITLE
            ),
            _CONFIGDATA
        );

        // Invalid if _TITLE empty.
        vm.expectRevert(IModule_v1.Module__InvalidMetadata.selector);
        module.init(
            _orchestrator,
            IModule_v1.Metadata(
                _MAJOR_VERSION, _MINOR_VERSION, _PATCH_VERSION, _URL, ""
            ),
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

    function testGrantModuleRoleBatched(bytes32 role, address[] memory addrs)
        public
    {
        vm.startPrank(address(this));

        for (uint i = 0; i < addrs.length; i++) {
            vm.assume(addrs[i] != address(0));
        }

        module.grantModuleRoleBatched(role, addrs);

        for (uint i = 0; i < addrs.length; i++) {
            bytes32 roleId = _authorizer.generateRoleId(address(module), role);
            bool isAuthorized =
                _authorizer.checkRoleMembership(roleId, addrs[i]);
            assertTrue(isAuthorized);
        }

        vm.stopPrank();
    }

    function testRevokeModuleRole(bytes32 role, address addr) public {
        vm.assume(addr != address(0));

        vm.startPrank(address(this));

        module.grantModuleRole(role, addr);

        bytes32 roleId = _authorizer.generateRoleId(address(module), role);
        bool isAuthorizedBefore = _authorizer.checkRoleMembership(roleId, addr);
        assertTrue(isAuthorizedBefore);

        module.revokeModuleRole(role, addr);

        bool isAuthorizedAfter = _authorizer.checkRoleMembership(roleId, addr);
        assertFalse(isAuthorizedAfter);

        vm.stopPrank();
    }

    function testRevokeModuleRoleBatched(bytes32 role, address[] memory addrs)
        public
    {
        vm.startPrank(address(this));

        for (uint i = 0; i < addrs.length; i++) {
            vm.assume(addrs[i] != address(0));
        }

        module.grantModuleRoleBatched(role, addrs);

        bytes32 roleId = _authorizer.generateRoleId(address(module), role);

        for (uint i = 0; i < addrs.length; i++) {
            bool isAuthorizedBefore =
                _authorizer.checkRoleMembership(roleId, addrs[i]);
            assertTrue(isAuthorizedBefore);
        }

        module.revokeModuleRoleBatched(role, addrs);

        for (uint i = 0; i < addrs.length; i++) {
            bool isAuthorizedAfter =
                _authorizer.checkRoleMembership(roleId, addrs[i]);
            assertFalse(isAuthorizedAfter);
        }

        vm.stopPrank();
    }

    //--------------------------------------------------------------------------
    // FeeManager

    function testGetFeeManagerCollateralFeeData(bytes4 functionSelector)
        public
    {
        uint setFee = 100;
        address treasury = makeAddr("customTreasury");

        // Set treasury
        feeManager.setWorkflowTreasury(address(_orchestrator), treasury);

        // set fee
        feeManager.setCollateralWorkflowFee(
            address(_orchestrator),
            address(module),
            functionSelector,
            true,
            setFee
        );

        (uint returnFee, address returnTreasury) =
            module.original_getFeeManagerCollateralFeeData(functionSelector);

        assertEq(returnFee, setFee);
        assertEq(returnTreasury, treasury);
    }

    function testGetFeeManagerIssuanceFeeData(bytes4 functionSelector) public {
        uint setFee = 100;
        address treasury = makeAddr("customTreasury");

        // Set treasury
        feeManager.setWorkflowTreasury(address(_orchestrator), treasury);

        // set fee
        feeManager.setIssuanceWorkflowFee(
            address(_orchestrator),
            address(module),
            functionSelector,
            true,
            setFee
        );

        (uint returnFee, address returnTreasury) =
            module.original_getFeeManagerIssuanceFeeData(functionSelector);

        assertEq(returnFee, setFee);
        assertEq(returnTreasury, treasury);
    }

    //--------------------------------------------------------------------------
    // ERC2771

    function test_msgSender(address signer, address sender, bool fromForwarder)
        public
    {
        vm.assume(sender != address(_forwarder));

        // Activate the trustedForwarder connection
        _orchestrator.flipConnectToTrustedForwarder();

        // setup function signature that will trigger the _msgSender
        bytes memory originalCallData =
            abi.encodeWithSignature("original_msgSender()");

        // this should add the 20 bytes of the address to the end of the calldata
        bytes memory metaTxCallData = abi.encodePacked(originalCallData, signer);

        if (fromForwarder) {
            sender = address(_forwarder);
        }
        // use call to properly use the added address at the end of the callData
        vm.prank(sender);
        (bool success, bytes memory returndata) =
            address(module).call(metaTxCallData);

        assertTrue(success);

        // Decode the correct perceivedAddress out of the call returndata
        address perceivedSender = abi.decode(returndata, (address));

        if (fromForwarder) {
            // If from Forwarder it should recognize the signer as the sender
            assertEq(perceivedSender, signer);
        } else {
            // If not it should be the sender
            assertEq(perceivedSender, sender);
        }
    }

    function test_msgData(address signer, address sender, bool fromForwarder)
        public
    {
        vm.assume(sender != address(_forwarder));

        // Activate the trustedForwarder connection
        _orchestrator.flipConnectToTrustedForwarder();

        // setup function signature that will trigger the _msgData
        bytes memory originalCallData =
            abi.encodeWithSignature("original_msgData()");

        // this should add the 20 bytes of the address to the end of the calldata
        bytes memory metaTxCallData = abi.encodePacked(originalCallData, signer);

        if (fromForwarder) {
            sender = address(_forwarder);
        }
        // use call to properly use the added address at the end of the callData
        vm.prank(sender);
        (bool success, bytes memory returndata) =
            address(module).call(metaTxCallData);

        assertTrue(success);

        // Decode the correct perceivedData out of the call returndata
        bytes memory perceivedData = abi.decode(returndata, (bytes));

        if (fromForwarder) {
            // If from Forwarder it should have clipped the data to the size before the signer was added
            assertEq(perceivedData, originalCallData);
        } else {
            // If not it should be full data without the clipping
            assertEq(perceivedData, metaTxCallData);
        }
    }

    //--------------------------------------------------------------------------
    // Modifier

    /* Test modifier onlyPaymentClient
        ├── given the caller is not a PaymentClient
        │   └── when the function modifierOnlyPaymentClientCheck() gets called
        │       └── then it should revert
        └── given the caller is a PaymentClient module
            └── and the PaymentClient module is not registered in the Orchestrator
                └── when the function modifierOnlyPaymentClientCheck() gets called
                    └── then it should revert
    */

    function testOnlyPaymentClientModifier_worksGivenCallerIsNotPaymentClient(
        address _notPaymentClient
    ) public {
        vm.prank(address(_notPaymentClient));
        vm.expectRevert(IModule_v1.Module__OnlyCallableByPaymentClient.selector);
        module.modifierOnlyPaymentClientCheck();
    }

    function testOnlyPaymentClientModifier_worksGivenCallerIsPaymentClientButNotRegisteredModule(
    ) public {
        ERC20PaymentClientBaseV2Mock _erc20PaymentClientMock =
            new ERC20PaymentClientBaseV2Mock();

        vm.prank(address(_erc20PaymentClientMock));
        vm.expectRevert(IModule_v1.Module__OnlyCallableByPaymentClient.selector);
        module.modifierOnlyPaymentClientCheck();
    }

    function testValidAddress(address adr) public {
        if (adr == address(0) || adr == address(module)) {
            vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        }
        module.modifierOnlyValidAddressCheck(adr);
    }
}
