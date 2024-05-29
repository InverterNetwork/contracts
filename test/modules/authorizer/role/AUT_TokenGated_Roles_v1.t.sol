// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";

import {AUT_RolesV1Test} from "test/modules/authorizer/role/AUT_Roles_v1.t.sol";

// SuT
import {
    AUT_TokenGated_Roles_v1,
    IAUT_TokenGated_Roles_v1
} from "@aut/role/AUT_TokenGated_Roles_v1.sol";

import {AUT_Roles_v1, IAuthorizer_v1} from "@aut/role/AUT_Roles_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {IAccessControl} from "@oz/access/IAccessControl.sol";
import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

// Internal Dependencies
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
// Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";
// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ERC721Mock} from "test/utils/mocks/ERC721Mock.sol";
import {ModuleV1Mock} from "test/utils/mocks/modules/base/ModuleV1Mock.sol";
import {FundingManagerV1Mock} from
    "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {PaymentProcessorV1Mock} from
    "test/utils/mocks/modules/PaymentProcessorV1Mock.sol";
import {GovernorV1Mock} from "test/utils/mocks/external/GovernorV1Mock.sol";

// Run through the AUT_Roles_v1 tests with the AUT_TokenGated_Roles_v1
contract AUT_TokenGated_RolesV1Test is AUT_RolesV1Test {
    function setUp() public override {
        //==== We use the AUT_TokenGated_Roles_v1 as a regular AUT_Roles_v1 =====
        address authImpl = address(new AUT_TokenGated_Roles_v1());
        _authorizer = AUT_Roles_v1(Clones.clone(authImpl));
        //==========================================================================

        address propImpl = address(new Orchestrator_v1(address(0)));
        _orchestrator = Orchestrator_v1(Clones.clone(propImpl));
        ModuleV1Mock module = new ModuleV1Mock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        _orchestrator.init(
            _ORCHESTRATOR_ID,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor,
            governor
        );

        address initialAuth = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, initialManager)
        );
        assertEq(
            _authorizer.hasRole(_authorizer.getManagerRole(), address(this)),
            true
        );
        assertEq(_authorizer.hasRole(_authorizer.getOwnerRole(), ALBA), true);
        assertEq(
            _authorizer.hasRole(_authorizer.getOwnerRole(), address(this)),
            false
        );
    }
}

contract TokenGatedAUT_RoleV1Test is Test {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // Mocks
    AUT_TokenGated_Roles_v1 _authorizer;
    Orchestrator_v1 internal _orchestrator = new Orchestrator_v1(address(0));
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    FundingManagerV1Mock _fundingManager = new FundingManagerV1Mock();
    PaymentProcessorV1Mock _paymentProcessor = new PaymentProcessorV1Mock();
    GovernorV1Mock internal governor = new GovernorV1Mock();

    ModuleV1Mock mockModule = new ModuleV1Mock();

    address ALBA = address(0xa1ba); //default authorized person
    address BOB = address(0xb0b); // example person
    address CLOE = address(0xc10e); // example person

    ERC20Mock internal roleToken =
        new ERC20Mock("Inverters With Benefits", "IWB");
    ERC721Mock internal roleNft =
        new ERC721Mock("detrevnI epA thcaY bulC", "EPA");

    bytes32 immutable ROLE_TOKEN = "ROLE_TOKEN";
    bytes32 immutable ROLE_NFT = "ROLE_NFT";

    // Orchestrator_v1 Constants
    uint internal constant _ORCHESTRATOR_ID = 1;
    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule_v1.Metadata _METADATA =
        IModule_v1.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the token-gating of a role changes.
    /// @param role The role that was modified.
    /// @param newValue The new value of the role.
    event ChangedTokenGating(bytes32 role, bool newValue);

    /// @notice Event emitted when the threshold of a token-gated role changes.
    /// @param role The role that was modified.
    /// @param token The token for which the threshold was modified.
    /// @param newValue The new value of the threshold.
    event ChangedTokenThreshold(bytes32 role, address token, uint newValue);

    function setUp() public {
        address authImpl = address(new AUT_TokenGated_Roles_v1());
        _authorizer = AUT_TokenGated_Roles_v1(Clones.clone(authImpl));
        address propImpl = address(new Orchestrator_v1(address(0)));
        _orchestrator = Orchestrator_v1(Clones.clone(propImpl));
        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);
        _orchestrator.init(
            _ORCHESTRATOR_ID,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor,
            governor
        );

        address initialAuth = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IOrchestrator_v1(_orchestrator),
            _METADATA,
            abi.encode(initialAuth, initialManager)
        );

        assertEq(
            _authorizer.hasRole(_authorizer.getManagerRole(), address(this)),
            true
        );
        assertEq(_authorizer.hasRole(_authorizer.getOwnerRole(), ALBA), true);
        assertEq(
            _authorizer.hasRole(_authorizer.getOwnerRole(), address(this)),
            false
        );

        //We mint some tokens: First, two different amounts of ERC20
        roleToken.mint(BOB, 1000);
        roleToken.mint(CLOE, 10);

        //Then, a ERC721 for BOB
        roleNft.mint(BOB);
    }

    function testSupportsInterface() public {
        assertTrue(
            _authorizer.supportsInterface(
                type(IAUT_TokenGated_Roles_v1).interfaceId
            )
        );
    }

    //-------------------------------------------------
    // Helper Functions

    // function set up tokenGated role with threshold
    function setUpTokenGatedRole(
        address module,
        bytes32 role,
        address token,
        uint threshold
    ) internal returns (bytes32) {
        bytes32 roleId = _authorizer.generateRoleId(module, role);
        vm.startPrank(module);

        vm.expectEmit();
        emit ChangedTokenGating(roleId, true);
        emit ChangedTokenThreshold(roleId, address(token), threshold);

        _authorizer.makeRoleTokenGatedFromModule(role);
        _authorizer.grantTokenRoleFromModule(role, address(token), threshold);
        vm.stopPrank();
        return roleId;
    }

    //function set up nftGated role
    function setUpNFTGatedRole(address module, bytes32 role, address nft)
        internal
        returns (bytes32)
    {
        bytes32 roleId = _authorizer.generateRoleId(module, role);
        vm.startPrank(module);

        _authorizer.makeRoleTokenGatedFromModule(role);
        _authorizer.grantTokenRoleFromModule(role, address(nft), 1);
        vm.stopPrank();
        return roleId;
    }

    function makeAddressDefaultAdmin(address who) public {
        bytes32 adminRole = _authorizer.DEFAULT_ADMIN_ROLE();
        vm.prank(ALBA);
        _authorizer.grantRole(adminRole, who);
        assertTrue(_authorizer.hasRole(adminRole, who));
    }

    // -------------------------------------
    // State change and validation tests

    //test make role token gated

    function testMakeRoleTokenGated() public {
        bytes32 roleId_1 = setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), 500
        );
        assertTrue(_authorizer.isTokenGated(roleId_1));

        bytes32 roleId_2 =
            setUpNFTGatedRole(address(mockModule), ROLE_NFT, address(roleNft));
        assertTrue(_authorizer.isTokenGated(roleId_2));
    }

    // test admin setTokenGating
    function testSetTokenGatingByAdmin() public {
        // we set CLOE as admin
        makeAddressDefaultAdmin(CLOE);

        //we set and unset on an empty role

        bytes32 roleId = _authorizer.generateRoleId(address(mockModule), "0x00");

        //now we make it tokengated as admin
        vm.prank(CLOE);

        vm.expectEmit();
        emit ChangedTokenGating(roleId, true);

        _authorizer.setTokenGated(roleId, true);

        assertTrue(_authorizer.isTokenGated(roleId));

        //and revert the change
        vm.prank(CLOE);

        vm.expectEmit();
        emit ChangedTokenGating(roleId, false);

        _authorizer.setTokenGated(roleId, false);

        assertFalse(_authorizer.isTokenGated(roleId));
    }

    //test makeTokenGated fails if not empty
    function testMakingFunctionTokenGatedFailsIfAlreadyInUse() public {
        bytes32 roleId =
            _authorizer.generateRoleId(address(mockModule), ROLE_TOKEN);

        //we switch on self-management and whitelist an address
        vm.startPrank(address(mockModule));
        _authorizer.grantRoleFromModule(ROLE_TOKEN, CLOE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotEmpty
                    .selector
            )
        );
        _authorizer.makeRoleTokenGatedFromModule(ROLE_TOKEN);
        assertFalse(_authorizer.isTokenGated(roleId));

        //we revoke the whitelist
        _authorizer.revokeRoleFromModule(ROLE_TOKEN, CLOE);

        // now it works:
        _authorizer.makeRoleTokenGatedFromModule(ROLE_TOKEN);
        assertTrue(_authorizer.isTokenGated(roleId));
    }
    // smae but with admin

    function testSetTokenGatedFailsIfRoleAlreadyInUse() public {
        // we set BOB as admin
        makeAddressDefaultAdmin(BOB);

        bytes32 roleId =
            _authorizer.generateRoleId(address(mockModule), ROLE_TOKEN);

        //we switch on self-management and whitelist an address
        vm.prank(address(mockModule));
        _authorizer.grantRoleFromModule(ROLE_TOKEN, CLOE);

        vm.startPrank(BOB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotEmpty
                    .selector
            )
        );
        _authorizer.setTokenGated(roleId, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotEmpty
                    .selector
            )
        );
        _authorizer.setTokenGated(roleId, false);

        //we revoke the whitelist
        _authorizer.revokeRole(roleId, CLOE);

        // now it works:
        _authorizer.setTokenGated(roleId, true);
        assertTrue(_authorizer.isTokenGated(roleId));

        _authorizer.setTokenGated(roleId, false);
        assertFalse(_authorizer.isTokenGated(roleId));
    }

    // test interface enforcement when granting role
    // -> yes case
    function testCanAddTokenWhenTokenGated() public {
        setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), 500
        );
        setUpNFTGatedRole(address(mockModule), ROLE_NFT, address(roleNft));
    }
    // -> no case

    function testCannotAddNonTokenWhenTokenGated() public {
        setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), 500
        );

        vm.prank(address(mockModule));
        //First, the call to the interface reverts without reason
        vm.expectRevert();
        //Then the contract handles the reversion and sends the correct error message
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidToken
                    .selector,
                CLOE
            )
        );
        _authorizer.grantRoleFromModule(ROLE_TOKEN, CLOE);
    }

    function testAdminCannotAddNonTokenWhenTokenGated() public {
        // we set BOB as admin
        makeAddressDefaultAdmin(BOB);

        bytes32 roleId = setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), 500
        );

        vm.prank(BOB);
        //First, the call to the interface reverts without reason
        vm.expectRevert();
        //Then the contract handles the reversion and sends the correct error message
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidToken
                    .selector,
                CLOE
            )
        );
        _authorizer.grantRole(roleId, CLOE);
    }

    // Check setting the threshold
    // yes case
    function testSetThreshold() public {
        bytes32 roleId = setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), 500
        );
        assertEq(_authorizer.getThresholdValue(roleId, address(roleToken)), 500);
    }

    // invalid threshold from module

    function testSetThresholdFailsIfInvalid() public {
        bytes32 role = ROLE_TOKEN;
        vm.startPrank(address(mockModule));
        _authorizer.makeRoleTokenGatedFromModule(role);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidThreshold
                    .selector,
                0
            )
        );
        _authorizer.grantTokenRoleFromModule(role, address(roleToken), 0);

        vm.stopPrank();
    }
    // invalid threshold from admin

    function testSetThresholdFromAdminFailsIfInvalid() public {
        // we set BOB as admin
        makeAddressDefaultAdmin(BOB);
        //First we set up a valid role
        bytes32 roleId = setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), 500
        );

        // and we try to break it
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidThreshold
                    .selector,
                0
            )
        );
        _authorizer.setThreshold(roleId, address(roleToken), 0);
    }

    function testSetThresholdFailsIfNotTokenGated() public {
        // we set BOB as admin
        makeAddressDefaultAdmin(BOB);

        vm.prank(address(mockModule));
        //We didn't make the role token-gated beforehand
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotTokenGated
                    .selector
            )
        );
        _authorizer.grantTokenRoleFromModule(
            ROLE_TOKEN, address(roleToken), 500
        );

        //also fails for the admin
        bytes32 roleId =
            _authorizer.generateRoleId(address(mockModule), ROLE_TOKEN);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotTokenGated
                    .selector
            )
        );
        _authorizer.setThreshold(roleId, address(roleToken), 500);
    }

    // Test setThresholdFromModule

    function testSetThresholdFromModule() public {
        bytes32 roleId = setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), 500
        );
        vm.prank(address(mockModule));
        _authorizer.setThresholdFromModule(ROLE_TOKEN, address(roleToken), 1000);
        assertEq(
            _authorizer.getThresholdValue(roleId, address(roleToken)), 1000
        );
    }

    // invalid threshold from module

    function testSetThresholdFromModuleFailsIfInvalid() public {
        bytes32 role = ROLE_TOKEN;
        vm.startPrank(address(mockModule));
        _authorizer.makeRoleTokenGatedFromModule(role);

        _authorizer.grantTokenRoleFromModule(role, address(roleToken), 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__InvalidThreshold
                    .selector,
                0
            )
        );
        _authorizer.setThresholdFromModule(ROLE_TOKEN, address(roleToken), 0);

        vm.stopPrank();
    }

    function testSetThresholdFromModuleFailsIfNotTokenGated() public {
        // we set BOB as admin
        makeAddressDefaultAdmin(BOB);

        vm.prank(address(mockModule));
        //We didn't make the role token-gated beforehand
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__RoleNotTokenGated
                    .selector
            )
        );
        _authorizer.setThresholdFromModule(ROLE_TOKEN, address(roleToken), 500);
    }

    // Threshold state checks:
    // Cannot grant role if threshold is set to zero

    function testGrantTokenRoleFailsIfThresholdWouldBeZero() public {
        bytes32 role = ROLE_TOKEN;

        //Make the role token-gated, but don't set a token with grantRoleFromModule()
        vm.prank(address(mockModule));
        _authorizer.makeRoleTokenGatedFromModule(role);

        bytes32 storedRoleId =
            _authorizer.generateRoleId(address(mockModule), role);

        // Now we make BOB admin of the role
        makeAddressDefaultAdmin(BOB);

        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAUT_TokenGated_Roles_v1
                    .Module__AUT_TokenGated_Roles__TokenRoleMustHaveThreshold
                    .selector,
                storedRoleId,
                address(roleToken)
            )
        );
        _authorizer.grantRole(storedRoleId, address(roleToken)); // BOB tries to circumvent setting a threshold

        vm.stopPrank();
    }

    // Threshold is zero after revoking role

    function testThresholdStateGetsDeletedOnRevoke() public {
        bytes32 role = ROLE_TOKEN;
        bytes32 moduleRoleId =
            _authorizer.generateRoleId(address(mockModule), role);

        assertEq(
            _authorizer.getThresholdValue(moduleRoleId, address(roleToken)), 0
        );

        vm.startPrank(address(mockModule));

        //Make the role token-gated with a threshold of 500
        _authorizer.makeRoleTokenGatedFromModule(role);
        _authorizer.grantTokenRoleFromModule(role, address(roleToken), 500);

        assertEq(
            _authorizer.getThresholdValue(moduleRoleId, address(roleToken)), 500
        );

        _authorizer.revokeRoleFromModule(role, address(roleToken));

        assertEq(
            _authorizer.getThresholdValue(moduleRoleId, address(roleToken)), 0
        );

        // Grant the same role again, with different Threshold
        _authorizer.grantTokenRoleFromModule(role, address(roleToken), 250);

        assertEq(
            _authorizer.getThresholdValue(moduleRoleId, address(roleToken)), 250
        );

        vm.stopPrank();
    }

    //Test Authorization

    // Test token authorization
    // -> yes case
    function testFuzzTokenAuthorization(
        uint threshold,
        address[] calldata callers,
        uint[] calldata amounts
    ) public {
        vm.assume(callers.length <= amounts.length);
        vm.assume(threshold != 0);

        //This implcitly confirms ERC20 compatibility

        //We burn the tokens created on setup
        roleToken.burn(BOB, 1000);
        roleToken.burn(CLOE, 10);

        bytes32 roleId = setUpTokenGatedRole(
            address(mockModule), ROLE_TOKEN, address(roleToken), threshold
        );

        for (uint i = 0; i < callers.length; i++) {
            if (callers[i] == address(0)) {
                //cannot mint to 0 address
                continue;
            }

            roleToken.mint(callers[i], amounts[i]);

            //we ensure both ways to check give the same result
            vm.prank(address(mockModule));
            bool result = _authorizer.hasModuleRole(ROLE_TOKEN, callers[i]);
            assertEq(result, _authorizer.hasTokenRole(roleId, callers[i]));

            // we verify the result ir correct
            if (amounts[i] >= threshold) {
                assertTrue(result);
            } else {
                assertFalse(result);
            }

            // we burn the minted tokens to avoid overflows
            roleToken.burn(callers[i], amounts[i]);
        }
    }

    // Test NFT authorization
    // -> yes case
    // -> no case
    function testFuzzNFTAuthorization(
        address[] calldata callers,
        bool[] calldata hasNFT
    ) public {
        vm.assume(callers.length < 50);
        vm.assume(callers.length <= hasNFT.length);

        //This is similar to the function above, but in this case we just do a yes/no check
        //This implcitly confirms ERC721 compatibility

        //We burn the token created on setup
        roleNft.burn(roleNft.idCounter() - 1);

        bytes32 roleId =
            setUpNFTGatedRole(address(mockModule), ROLE_NFT, address(roleNft));

        for (uint i = 0; i < callers.length; i++) {
            if (callers[i] == address(0)) {
                //cannot mint to 0 address
                continue;
            }
            if (hasNFT[i]) {
                roleNft.mint(callers[i]);
            }

            //we ensure both ways to check give the same result
            vm.prank(address(mockModule));
            bool result = _authorizer.hasModuleRole(ROLE_NFT, callers[i]);
            assertEq(result, _authorizer.hasTokenRole(roleId, callers[i]));

            // we verify the result ir correct
            if (hasNFT[i]) {
                assertTrue(result);
            } else {
                assertFalse(result);
            }

            // If we minted a token we burn it to guarantee a clean slate in case of address repetition
            if (hasNFT[i]) {
                roleNft.burn(roleNft.idCounter() - 1);
            }
        }
    }
}
