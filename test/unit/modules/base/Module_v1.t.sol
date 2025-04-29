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
} from "@unitTest/modules/ModuleTest.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";

import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

// Mocks
import {ModuleV1Mock} from "@mocks/modules/base/ModuleV1Mock.sol";
import {FundingManagerV1Mock} from
    "@mocks/modules/fundingManager/FundingManagerV1Mock.sol";
import {AuthorizerV1Mock} from "@mocks/modules/authorizer/AuthorizerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "@mocks/modules/paymentProcessor/PaymentProcessorV1Mock.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

// Errors
import {OZErrors} from "@testUtilities/OZErrors.sol";

contract ModuleBaseV1Test is ModuleTest {
    ///////////////////////////////////////////////////////////////////////////
    // State

    // SuT
    ModuleV1Mock module;

    bytes _CONFIGDATA = bytes("");

    ///////////////////////////////////////////////////////////////////////////
    // Setup

    function setUp() public {
        address impl = address(new ModuleV1Mock());
        module = ModuleV1Mock(Clones.clone(impl));

        _setUpOrchestrator(module);

        vm.expectEmit(true, true, true, false);
        emit IModule_v1.ModuleInitialized(address(_orchestrator), _METADATA);

        module.init(_orchestrator, _METADATA, _CONFIGDATA);
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test Initialization

    /*
    Test: SupportsInterface
    └── Given: The interfaceId is IModule_v1
        └── When: the function supportsInterface is called
            └── Then: the function should return true
    */
    function testSupportsInterface() public override(ModuleTest) {
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

    /////////////////////////////////////////////////////////////////////////////
    // Test Modifier

    /*
    Test: permissioned
    ├── Given: modifierPermissionedCheck is executed via call with a valid selector, but random data
    ├── And: The call sender is randomised
    └── And: The Caller is permissioned to call the function
        └── When: The function modifierPermissionedCheck is called
            └── Then: the function should not revert, because the sender and only the function selector were correctly passed
    */
    function testPermissioned_modifier(address caller_, bytes memory data_)
        public
    {
        // Assume that the calldata is at least 4 bytes long
        vm.assume(data_.length >= 4);

        bytes4 targetSelector = ModuleV1Mock.modifierPermissionedCheck.selector;

        // Proof
        _authorizer.setHasPermission(
            caller_, address(module), targetSelector, true
        );

        // Replace the msg.data function selector with the correct one
        for (uint i = 0; i < 4; i++) {
            data_[i] = targetSelector[i];
        }

        // Expect no revert
        vm.prank(caller_);
        address(module).call(data_);
    }

    /* 
    Test modifier onlyPaymentClient
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

    /*
    Test: validAddress
    └── Given: The address is either the zero address or the module address
        └── When: validAddress is called
            └── Then: The function should revert
    */

    function testValidAddress(address adr) public {
        if (adr == address(0) || adr == address(module)) {
            vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        }
        module.modifierOnlyValidAddressCheck(adr);
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test External Functions

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter - Module State

    /*
    Test: identifier
    └── When: the function identifier is called
        └── Then: the function should return the identifier
    */
    // Trivial
    /*
    Test: version
    └── When: the function version is called
        └── Then: the function should return the version
    */
    // Trivial
    /*
    Test: url
    └── When: the function url is called
        └── Then: the function should return the url
    */
    // Trivial
    /*
    Test: title
    └── When: the function title is called
        └── Then: the function should return the title
    */
    // Trivial
    /*
    Test: orchestrator
    └── When: the function orchestrator is called
        └── Then: the function should return the orchestrator
    */
    // Trivial

    //--------------------------------------------------------------------------
    // Getter - ERC2771 Context Upgradeable Overrides

    //@todo This test is weird and probably needs to be moved to a different test file
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

    //@todo This test is weird and probably needs to be moved to a different test file
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

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Out of Order

    /*
    Test: grantModuleRole
    └── When: grantModuleRole is called
        └── Then: The function should revert with Module_FunctionDeprecated
        */
    function testGrantModuleRole_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        module.grantModuleRole(bytes32(uint(0)), address(0));
    }

    /*
    Test: grantModuleRoleBatched
    └── When: grantModuleRoleBatched is called
        └── Then: The function should revert with Module_FunctionDeprecated
        */
    function testGrantModuleRoleBatched_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        module.grantModuleRoleBatched(bytes32(uint(0)), new address[](0));
    }

    /*
    Test: revokeModuleRole
    └── When: revokeModuleRole is called
        └── Then: The function should revert with Module_FunctionDeprecated
        */
    function testRevokeModuleRole_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        module.revokeModuleRole(bytes32(uint(0)), address(0));
    }

    /*
    Test: revokeModuleRoleBatched
    └── When: revokeModuleRoleBatched is called
        └── Then: The function should revert with Module_FunctionDeprecated
        */
    function testRevokeModuleRoleBatched_Deprecated() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__FunctionDeprecated.selector
            )
        );
        module.revokeModuleRoleBatched(bytes32(uint(0)), new address[](0));
    }

    // ========================================================================
    // Internal Functions

    // ------------------------------------------------------------------------
    // Internal - Fees

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
            module._getFeeManagerCollateralFeeData_exposed(functionSelector);

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
            module._getFeeManagerIssuanceFeeData_exposed(functionSelector);

        assertEq(returnFee, setFee);
        assertEq(returnTreasury, treasury);
    }

    // ------------------------------------------------------------------------
    // Internal - Authorization

    /*
    Test: _checkAuthorization_
    └── Given: Authorizer hasPermission() is mocked
        ├── When: _checkAuthorization_ is called
        └── And: Authorizer hasPermission() returns false
            ├── Then: It should forward the function selector properly
            └── And: The function should revert
    */
    function test_checkAuthorization_hasPermissionMocked(
        bool hasPermission_,
        address caller_,
        bytes calldata data_
    ) public {
        vm.assume(data_.length >= 4);

        _authorizer.setHasPermission(
            caller_, address(module), bytes4(data_[0:4]), hasPermission_
        );

        if (!hasPermission_) {
            vm.expectRevert(IModule_v1.Module__NotPermissioned.selector);
        }

        module._checkAuthorization_exposed(caller_, data_);
    }
}
