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

import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {IAUT_TokenGated_Roles_v1} from
    "@aut/role/interfaces/IAUT_TokenGated_Roles_v1.sol";

import {TokenInterface} from "@aut/role/AUT_TokenGated_Roles_v1.sol";

// SuT
import {AUT_TokenGated_Roles_v1_Exposed} from
    "@mocks/modules/authorizer/AUT_TokenGated_Roles_v1_Exposed.sol";

// Mocks
import {FundingManagerV1Mock} from
    "@mocks/modules/fundingManager/FundingManagerV1Mock.sol";
import {AuthorizerV1Mock} from "@mocks/modules/authorizer/AuthorizerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "@mocks/modules/paymentProcessor/PaymentProcessorV1Mock.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {TokenInterfaceMock} from
    "@mocks/modules/authorizer/TokenInterfaceMock.sol";

// Errors
import {OZErrors} from "@testUtilities/OZErrors.sol";

// External Dependencies
import {IAccessControl} from "@oz/access/IAccessControl.sol";

contract AUT_TokenGated_Roles_v1_Test is ModuleTest {
    ///////////////////////////////////////////////////////////////////////////
    // State

    // SuT
    AUT_TokenGated_Roles_v1_Exposed _authSuT;

    // Constants
    address _bob = makeAddr("Bob");

    // Addresses

    // Bob and Alice can Access
    bytes4 _selector1 = bytes4(keccak256("selector1()"));
    // Alice can access
    bytes4 _selector2 = bytes4(keccak256("selector2()"));
    // No Permissions
    bytes4 _selector3 = bytes4(keccak256("selector3()"));
    // Public Role can access
    bytes4 _selector4 = bytes4(keccak256("selector4()"));

    ///////////////////////////////////////////////////////////////////////////
    // Setup

    function setUp() public {
        address impl = address(new AUT_TokenGated_Roles_v1_Exposed());
        _authSuT = AUT_TokenGated_Roles_v1_Exposed(Clones.clone(impl));

        // initiate orchestrator without extra Module
        _setUpOrchestrator();

        // Init SuT
        // Initial Admin is this contract
        _authSuT.init(_orchestrator, _METADATA, abi.encode(address(this)));

        // Change Authorizer of Module Test to SuT
        _orchestrator.initiateSetAuthorizerWithTimelock(
            IAuthorizer_v1(_authSuT)
        );
        vm.warp(72 hours + 1);
        _orchestrator.executeSetAuthorizer(IAuthorizer_v1(_authSuT));
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test Initialization

    /*
    Test: SupportsInterface
    └── Given: The interfaceId is IAuthorizer_v1
        └── When: the function supportsInterface is called
            └── Then: the function should return true
    */
    function testSupportsInterface() public override(ModuleTest) {
        assertTrue(
            _authSuT.supportsInterface(
                type(IAUT_TokenGated_Roles_v1).interfaceId
            )
        );
    }

    /*
    Test: Init
    └── When: the function init is called
        └── Then: the function should set the initial admin
    */
    function testInit() public override {
        // Check that the initial Admin is set
        assertTrue(_authSuT.hasRole(_authSuT.getAdminRole(), address(this)));
    }

    /*
    Test: ReinitFails
    └── When: the function init is called after the contract has been initialized
        └── Then: the function should revert
    */
    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        _authSuT.init(_orchestrator, _METADATA, abi.encode(address(this)));
    }
    /////////////////////////////////////////////////////////////////////////////
    // Test Modifier

    /* 
    Test: onlyEmptyRole Modifier
    └── Given: Role is not empty
        └── When: function with onlyEmptyRole modifier is called
            └── Then: the function should revert
    */
    function testOnlyEmptyRoleModifier(uint seed_) public {
        // Create address array
        address[] memory members = new address[](seed_ % 20);
        for (uint i; i < members.length; ++i) {
            members[i] = address(uint160(i));
        }

        // Create Role
        bytes32 roleId =
            _authSuT.createRole("Role", _authSuT.DEFAULT_ADMIN_ROLE(), members);

        if (members.length != 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAUT_TokenGated_Roles_v1
                        .Module__AUT_TokenGated_Roles__RoleNotEmpty
                        .selector
                )
            );
        }
        _authSuT.onlyEmptyRoleModifier_exposed(roleId);
    }

    /*
    Test notPublicRole Modifier
    └── Given: Role is public
        └── When: function with notPublicRole modifier is called
            └── Then: the function should revert
     */
    function testNotPublicRoleModifier() public {
        bytes32 roleId = _authSuT.PUBLIC_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleIsPublic
                    .selector
            )
        );
        _authSuT.notPublicRoleModifier_exposed(roleId);
    }

    /*
    Test: onlyTokenGated Modifier
    └── Given: Role is not token-gated
        └── When: function with onlyTokenGated modifier is called
            └── Then: the function should revert
    */
    function testOnlyTokenGatedModifier(bool isTokenGated_) public {
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Set token gated
        if (isTokenGated_) {
            _authSuT.setTokenGated(roleId, true);
        } else {
            // If not token gated, then the function should revert
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAUT_TokenGated_Roles_v1
                        .Module__AUT_TokenGated_Roles__RoleNotTokenGated
                        .selector
                )
            );
        }
        _authSuT.onlyTokenGatedModifier_exposed(roleId);
    }

    /*
    Test: validThreshold Modifier
    └── Given: Threshold is invalid
        └── When: function with validThreshold modifier is called
            └── Then: the function should revert
    */
    function testValidThresholdModifier(uint threshold_) public {
        if (threshold_ == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAUT_TokenGated_Roles_v1
                        .Module__AUT_TokenGated_Roles__InvalidThreshold
                        .selector,
                    threshold_
                )
            );
        }
        _authSuT.validThresholdModifier_exposed(threshold_);
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test External Functions

    // ========================================================================
    // Public Getter Functions

    /*
    Test: isTokenGated
    └── When: isTokenGated is called
        └── Then: Return if the role is token gated
    */
    function testIsTokenGated(bool isTokenGated_, bytes32 roleId_) public {
        // Public role cannot be token gated
        vm.assume(roleId_ != _authSuT.PUBLIC_ROLE());

        // Set token gated
        if (isTokenGated_) {
            _authSuT.setTokenGated_unrestricted(roleId_, true);
        }
        assertEq(_authSuT.isTokenGated(roleId_), isTokenGated_);
    }

    /*
    Test: hasTokenRole
    ├── Given: Role is not token gated
    │   └── When: hasTokenRole is called
    │       └── Then: It should revert (modifier in position check)
    └──  Given: Role is token gated
        └── When: hasTokenRole is called
            └── Then: It should call the internal function
    */
    function testHasTokenRole_ModifierInPositionChecks() public {
        // onlyTokenGated
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotTokenGated
                    .selector
            )
        );
        _authSuT.hasTokenRole(bytes32(uint(0)), address(0));
    }

    function testHasTokenRole_TokenGated_CallsInternalFunction(
        address who_,
        bool hasTokenRole_
    ) public {
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make Role token gated
        _authSuT.setTokenGated(roleId, true);

        // Create Token Interface Mock
        address token = address(new TokenInterfaceMock());

        // Set threshold
        _authSuT.setThreshold(roleId, token, 1);

        // Grant Role
        _authSuT.grantRole(roleId, token);

        if (hasTokenRole_) {
            // Give the address some tokens
            TokenInterfaceMock(token).setTokenBalance(who_, 1);
        }

        // Check that the role is granted
        assertEq(_authSuT.hasTokenRole(roleId, who_), hasTokenRole_);
    }

    /*
    Test: getThresholdValue
    └── When: getThresholdValue is called
        └── Then: Return the threshold value
    */
    function testGetThresholdValue(
        uint threshold_,
        bytes32 roleId_,
        address token_
    ) public {
        // Set threshold
        _authSuT.setThreshold_unrestricted(roleId_, token_, threshold_);

        assertEq(_authSuT.getThresholdValue(roleId_, token_), threshold_);
    }

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - TokenGated Settings

    /*
    Test: setTokenGated
    ├── Given: Caller is not permissioned
    │   └── When: setTokenGated is called
    │       └── Then: The call reverts (modifier in position check)
    ├── Given: Caller is permissioned
    ├── And: Role is not empty
    │   └── When: setTokenGated is called
    │       └── Then: The call reverts (modifier in position check)
    ├── Given: Caller is permissioned
    ├── And: Role is empty
    ├── And: Role is Public Role
    │   └── When: setTokenGated is called
    │       └── Then: The call reverts (modifier in position check)
    ├── Given: Caller is permissioned
    ├── And: Role is empty
    └── And: Role is not Public Role
        └── When: setTokenGated is called
            └── Then: The role becomes token gated
                └── And: An event is emitted
     */
    function testSetTokenGated_ModifierInPositionChecks() public {
        // permissioned
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(_bob);
        _authSuT.setTokenGated(bytes32(uint(0)), true);

        //idExists(roleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        _authSuT.setTokenGated(bytes32(uint(2)), true);

        // onlyEmptyRole(roleId_)

        // Create Role that is not empty
        address[] memory members = new address[](1);
        members[0] = _bob;
        bytes32 roleId =
            _authSuT.createRole("Role", _authSuT.DEFAULT_ADMIN_ROLE(), members);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotEmpty
                    .selector
            )
        );
        _authSuT.setTokenGated(roleId, true);

        // notPublicRole(roleId_)
        roleId = _authSuT.PUBLIC_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleIsPublic
                    .selector
            )
        );
        _authSuT.setTokenGated(roleId, true);
    }

    function testSetTokenGated_Functionality() public {
        // Create Role that is empty
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit IAUT_TokenGated_Roles_v1.ChangedTokenGating(roleId, true);

        // Set token gated
        _authSuT.setTokenGated(roleId, true);
        assertTrue(_authSuT.isTokenGated(roleId));
    }

    /*
    Test: setThreshold
    ├── Given: Caller is not permissioned
    │   └── When: setThreshold is called
    │       └── Then: The call reverts (modifier in position check)
    └── Given: Caller is permissioned
        └── When: setThreshold is called
            └── Then: The underlying function is called (Check via event)
    */
    function testSetThreshold_ModifierInPositionChecks() public {
        // permissioned
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(_bob);
        _authSuT.setThreshold(bytes32(uint(0)), address(0), 0);

        //idExists(roleId_)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuthorizer_v1.Module__Authorizer__RoleIdNotExisting.selector
            )
        );
        _authSuT.setThreshold(bytes32(uint(2)), address(0), 0);
    }

    function testSetThreshold_Functionality() public {
        // Create Role that is empty
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make it token gated
        _authSuT.setTokenGated(roleId, true);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit IAUT_TokenGated_Roles_v1.ChangedTokenThreshold(
            roleId, address(0), 1
        );

        // Set threshold
        _authSuT.setThreshold(roleId, address(0), 1);
    }

    ///////////////////////////////////////////////////////////////////////////
    // Test Override Functions

    /*
    Test: hasRole
    ├── Given: Role is not token gated
    ├── And: The given address does not have the role
    │   └── When: hasRole is called
    │       └── Then: hasRole works like base contract
    ├── Given: Role is token gated
    ├── And: The given address has the role
    │   └── When: hasRole is called
    │       └── Then: hasRole works like base contract
    └── Given: Role is token gated
        └── When: hasRole is called
            └── Then: It should use the internal _hasTokenRole function
    */
    function testHasRole_NotTokenGated_AddressDoesNotHaveRole(address who_)
        public
    {
        // Check that address is not initial admin
        vm.assume(who_ != address(this));
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );
        assertFalse(_authSuT.hasRole(roleId, who_));
    }

    function testHasRole_NotTokenGated_AddressHasRole(address who_) public {
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );
        // Add address to role
        _authSuT.grantRole(roleId, who_);
        assertTrue(_authSuT.hasRole(roleId, who_));
    }

    function testHasRole_TokenGated_CallsInternalFunction(
        address who_,
        bool hasTokenRole_
    ) public {
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make Role token gated
        _authSuT.setTokenGated(roleId, true);

        // Create Token Interface Mock
        address token = address(new TokenInterfaceMock());

        // Set threshold
        _authSuT.setThreshold(roleId, token, 1);

        // Grant Role
        _authSuT.grantRole(roleId, token);

        if (hasTokenRole_) {
            // Give the address some tokens
            TokenInterfaceMock(token).setTokenBalance(who_, 1);
        }

        // Check that the role is granted
        assertEq(_authSuT.hasRole(roleId, who_), hasTokenRole_);
    }
    /*
    Test: grantRole
    ├── Given: Role is not token gated
    │   └── When: grantRole is called
    │       └── Then: Grant Role works like base contract
    ├── Given: Role is token gated
    ├── And: The given address has code size 0
    │   └── When: grantRole is called
    │       └── Then: The function should revert
    ├── Given: Role is token gated
    ├── And: The given address has code size > 0
    ├── And: The Threshold is 0 for the given address
    │   └── When: grantRole is called
    │       └── Then: The function should revert
    ├── Given: Role is token gated
    ├── And: The given address has code size > 0
    ├── And: The Threshold is > 0 for the given address
    ├── And: The given address does not implement the TokenInterface
    │   └── When: grantRole is called
    │       └── Then: The function should revert
    ├── Given: Role is token gated
    ├── And: the given address has code size > 0
    ├── And: The Threshold is > 0 for the given address
    └── And: The given address implements the TokenInterface
        └── When: grantRole is called
            └── Then: Grant Role works like base contract
    */

    function test_grantRole_NotTokenGated(address who_) public {
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Grant Role
        _authSuT.grantRole(roleId, who_);

        // Check that the role is granted
        assertTrue(
            _authSuT.exposed_AccessControlUpgradeable_hasRole(roleId, who_)
        );
    }

    function test_grantRole_CodeSizeZero(address who_) public {
        uint32 size;
        assembly {
            size := extcodesize(who_)
        }
        vm.assume(size == 0);

        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make Role token gated
        _authSuT.setTokenGated(roleId, true);

        // Grant Role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidToken
                    .selector,
                address(who_)
            )
        );
        _authSuT.grantRole(roleId, who_);
    }

    function test_grantRole_TokenInterfaceThresholdZero() public {
        // Create Mock Token Interface
        TokenInterfaceMock tokenInterfaceMock = new TokenInterfaceMock();

        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make Role token gated
        _authSuT.setTokenGated(roleId, true);

        // Grant Role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__TokenRoleMustHaveThreshold
                    .selector,
                roleId,
                address(tokenInterfaceMock)
            )
        );

        _authSuT.grantRole(roleId, address(tokenInterfaceMock));
    }

    function test_grantRole_TokenInterfaceNotImplemented() public {
        // We pick a contract that definetly does not implement the interface
        address who_ = address(_orchestrator);
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make Role token gated
        _authSuT.setTokenGated(roleId, true);

        // Set threshold
        _authSuT.setThreshold(roleId, who_, 1);

        // Grant Role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidToken
                    .selector,
                who_
            )
        );
        _authSuT.grantRole(roleId, who_);
    }

    function test_grantRole_TokenInterfaceImplemented() public {
        // Create Mock Token Interface
        TokenInterfaceMock tokenInterfaceMock = new TokenInterfaceMock();

        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make Role token gated
        _authSuT.setTokenGated(roleId, true);

        // Set threshold
        _authSuT.setThreshold(roleId, address(tokenInterfaceMock), 1);

        // Grant Role
        _authSuT.grantRole(roleId, address(tokenInterfaceMock));

        // Check that the role is granted
        assertTrue(
            _authSuT.exposed_AccessControlUpgradeable_hasRole(
                roleId, address(tokenInterfaceMock)
            )
        );
    }

    /*
    Test: _revokeRole
    ├── Given: Role is not token gated
    │   └── When: revokeRole is called
    │       └── Then: Revoke Role works like base contract
    └── Given: Role is token gated
        └── When: revokeRole is called
            └── Then: The Threshold is set to 0
                └── And: An event is emitted
                    └── And: Revoke Role works like base contract
    */
    function test_revokeRole_NotTokenGated(address who_) public {
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );
        // Add address to role
        _authSuT.grantRole(roleId, who_);

        // Revoke Role
        _authSuT.revokeRole(roleId, who_);

        // Check that the role is revoked
        assertFalse(
            _authSuT.exposed_AccessControlUpgradeable_hasRole(roleId, who_)
        );
    }

    function test_revokeRole_TokenGated() public {
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        // Make Role token gated
        _authSuT.setTokenGated(roleId, true);

        // Create Token Interface Mock
        address who = address(new TokenInterfaceMock());

        // Set threshold
        _authSuT.setThreshold(roleId, who, 1);

        // Grant Role
        _authSuT.grantRole(roleId, who);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit IAUT_TokenGated_Roles_v1.ChangedTokenThreshold(roleId, who, 0);

        // Revoke Role
        _authSuT.revokeRole(roleId, who);

        // Check that threshold is set to 0
        assertEq(_authSuT.getThresholdValue(roleId, who), 0);

        // Check that the role is revoked
        assertFalse(
            _authSuT.exposed_AccessControlUpgradeable_hasRole(roleId, who)
        );
    }
    ///////////////////////////////////////////////////////////////////////////
    // Test Internal Functions

    // ------------------------------------------------------------------------
    // Internal - Upstream Function Implementations

    /*
    Test: _setThreshold
    ├── Given: The given roleId is not token gated
    │   └── When: _setThreshold is called
    │       └── Then: The call reverts (modifier in position check)
    ├── Given: The given roleId is token gated
    ├── And: the given threshold is invalid
    │   └── When: _setThreshold is called
    │       └── Then: The call reverts (modifier in position check)
    ├── Given: The given roleId is token gated
    └── And: the given threshold is valid
        └── When: _setThreshold is called
            └── Then: the threshold map is updated
                └── And: A event is emitted
    */
    function test_setThreshold_ModifierInPositionChecks() public {
        // onlyTokenGated(roleId_)
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotTokenGated
                    .selector
            )
        );
        _authSuT.exposed_setThreshold(roleId, address(0), 0);

        // validThreshold(threshold_)

        // Make role token gated
        _authSuT.setTokenGated(roleId, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidThreshold
                    .selector,
                0
            )
        );
        _authSuT.exposed_setThreshold(roleId, address(0), 0);
    }

    function test_setThreshold_Functionality(address token_, uint threshold_)
        public
    {
        // Make sure threshold_ is not zero
        vm.assume(threshold_ != 0);
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );
        // Make it TokenGated
        _authSuT.setTokenGated(roleId, true);

        vm.expectEmit(true, true, true, true);
        emit IAUT_TokenGated_Roles_v1.ChangedTokenThreshold(
            roleId, token_, threshold_
        );
        // Set Threshold
        _authSuT.setThreshold(roleId, token_, threshold_);

        assertEq(_authSuT.getThresholdValue(roleId, token_), threshold_);
    }

    /*
    Test: _hasTokenRole
    Invariant: Role can only contain TokenInterface addresses
    ├── Given: Role contains TokenInterface mock addresses
    ├── And: The token amount is less than the threshold
    │   └── When: _hasTokenRole is called
    │       └── Then: It should return false
    ├── Given: Role contains TokenInterface mock addresses
    └── And: The token amount of at least one of them is equal or higher than the threshold
        └── When: _hasTokenRole is called
            └── Then: It should return true
    */
    function test_hasTokenRole_TokenInterfacesWrongThreshold(
        uint[] memory thresholdAmounts_,
        address who_
    ) public {
        // Assume realistic number of token interface Mocks
        vm.assume(thresholdAmounts_.length < 50);
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );
        // Set token gated
        _authSuT.setTokenGated(roleId, true);

        // Create token interface mocks
        address[] memory tokenInterfaceMocks =
            new address[](thresholdAmounts_.length);

        for (uint i; i < thresholdAmounts_.length; ++i) {
            // Should the threshold be zero then set it to 1
            if (thresholdAmounts_[i] == 0) {
                thresholdAmounts_[i] = 1;
            }
            tokenInterfaceMocks[i] =
            _createTokenInterfaceMock_SetThresholdAmount_AddToMembers(
                roleId, thresholdAmounts_[i]
            );
        }

        // Should return false as target has no tokens in any of the mocks
        assertFalse(_authSuT.exposed_hasTokenRole(roleId, who_));
    }

    function test_hasTokenRole_WhoHasTokens(
        uint seed_,
        uint[] memory thresholdAmounts_,
        uint[] memory tokenAmounts_,
        address who_
    ) public {
        // Assume realistic number of token interface Mocks
        vm.assume(thresholdAmounts_.length > 0);

        // Cap the array to 50 elements
        if (thresholdAmounts_.length > 50) {
            uint[] memory cappedArr = new uint[](50); // Create new memory array

            for (uint i = 0; i < 50; i++) {
                cappedArr[i] = thresholdAmounts_[i]; // Copy elements into new array
            }

            thresholdAmounts_ = cappedArr;
        }

        vm.assume(tokenAmounts_.length <= thresholdAmounts_.length);
        // Create Role
        bytes32 roleId = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );
        // Set token gated
        _authSuT.setTokenGated(roleId, true);

        // Create token interface mocks
        address[] memory tokenInterfaceMocks =
            new address[](thresholdAmounts_.length);

        for (uint i; i < thresholdAmounts_.length; ++i) {
            // Should the threshold be zero then set it to 1
            if (thresholdAmounts_[i] == 0) {
                thresholdAmounts_[i] = 1;
            }
            tokenInterfaceMocks[i] =
            _createTokenInterfaceMock_SetThresholdAmount_AddToMembers(
                roleId, thresholdAmounts_[i]
            );
        }

        // Give the target some tokens
        for (uint i; i < tokenAmounts_.length; ++i) {
            TokenInterfaceMock(tokenInterfaceMocks[i]).setTokenBalance(
                who_, tokenAmounts_[i]
            );
        }

        // Make sure that the target has at least more or equal tokens in one of the mocks
        // Pick a random token interface mock
        address randomTokenInterfaceAddress =
            tokenInterfaceMocks[seed_ % thresholdAmounts_.length];
        // Pick the respective threshold amount
        uint thresholdAmountOfTokenInterfaceMock =
            thresholdAmounts_[seed_ % thresholdAmounts_.length];

        // Set the balance of the target to the threshold amount of the token interface mock
        TokenInterfaceMock(randomTokenInterfaceAddress).setTokenBalance(
            who_, thresholdAmountOfTokenInterfaceMock
        );

        // Should return true as target has thethreshold in at least one contract
        assertTrue(_authSuT.exposed_hasTokenRole(roleId, who_));
    }

    ///////////////////////////////////////////////////////////////////////////
    // Helper Functions

    /// @notice Creates a role with token gated set to true
    /// @return roleId_ The id of the created role
    function _createTokenGatedRole() internal returns (bytes32 roleId_) {
        // Create Role
        roleId_ = _authSuT.createRole(
            "Role", _authSuT.DEFAULT_ADMIN_ROLE(), new address[](0)
        );
        // Set token gated
        _authSuT.setTokenGated(roleId_, true);
    }

    /// @notice Creates a token interface mock, sets the threshold and adds it to the role
    /// @param  roleId_ The id of the role to add the token interface mock to
    /// @param  thresholdAmount_ The threshold amount to set
    /// @return tokenInterfaceMock_ The address of the token interface mock
    function _createTokenInterfaceMock_SetThresholdAmount_AddToMembers(
        bytes32 roleId_,
        uint thresholdAmount_
    ) internal returns (address tokenInterfaceMock_) {
        // Create token interface mock
        tokenInterfaceMock_ = address(new TokenInterfaceMock());

        // Set threshold
        _authSuT.setThreshold(roleId_, tokenInterfaceMock_, thresholdAmount_);

        // Add token interface mock to role
        _authSuT.grantRole(roleId_, tokenInterfaceMock_);
    }
}
