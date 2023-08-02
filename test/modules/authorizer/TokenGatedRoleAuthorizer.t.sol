// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";

import {RoleAuthorizerTest} from "test/modules/authorizer/RoleAuthorizer.t.sol";

// SuT
import {
    TokenGatedRoleAuthorizer,
    ITokenGatedRoleAuthorizer
} from "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";

import {
    RoleAuthorizer,
    IAuthorizer
} from "src/modules/authorizer/RoleAuthorizer.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
// Internal Dependencies
import {Orchestrator} from "src/orchestrator/Orchestrator.sol";
// Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";
// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ERC721Mock} from "test/utils/mocks/ERC721Mock.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

// Run through the RoleAuthorizer tests with the TokenGatedRoleAuthorizer
contract TokenGatedRoleAuthorizerUpstreamTests is RoleAuthorizerTest {
    function setUp() public override {
        //==== We use the TokenGatedRoleAuthorizer as a regular RoleAuthorizer =====
        address authImpl = address(new TokenGatedRoleAuthorizer());
        _authorizer = RoleAuthorizer(Clones.clone(authImpl));
        //==========================================================================

        address propImpl = address(new Orchestrator());
        _orchestrator = Orchestrator(Clones.clone(propImpl));
        ModuleMock module = new  ModuleMock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        _orchestrator.init(
            _ORCHESTRATOR_ID,
            _token,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor
        );

        address initialAuth = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IOrchestrator(_orchestrator),
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

contract TokenGatedRoleAuthorizerTest is Test {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // Mocks
    TokenGatedRoleAuthorizer _authorizer;
    Orchestrator internal _orchestrator = new Orchestrator();
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    FundingManagerMock _fundingManager = new FundingManagerMock();
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();

    ModuleMock mockModule = new ModuleMock();

    address ALBA = address(0xa1ba); //default authorized person
    address BOB = address(0xb0b); // example person
    address CLOE = address(0xc10e); // example person

    ERC20Mock internal roleToken =
        new ERC20Mock("Inverters With Benefits", "IWB");
    ERC721Mock internal roleNft =
        new ERC721Mock("detrevnI epA thcaY bulC", "EPA");

    enum ModuleRoles {
        ROLE_TOKEN,
        ROLE_NFT
    }

    // Orchestrator Constants
    uint internal constant _ORCHESTRATOR_ID = 1;
    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public {
        address authImpl = address(new TokenGatedRoleAuthorizer());
        _authorizer = TokenGatedRoleAuthorizer(Clones.clone(authImpl));
        address propImpl = address(new Orchestrator());
        _orchestrator = Orchestrator(Clones.clone(propImpl));
        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);
        _orchestrator.init(
            _ORCHESTRATOR_ID,
            _token,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor
        );

        address initialAuth = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IOrchestrator(_orchestrator),
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

        // By default, the mockModule will have self-management ON
        vm.prank(address(mockModule));
        _authorizer.toggleModuleSelfManagement();
    }

    //-------------------------------------------------
    // Helper Functions

    // function set up tokenGated role with threshold
    function setUpTokenGatedRole(
        address module,
        uint8 role,
        address token,
        uint threshold
    ) internal returns (bytes32) {
        bytes32 roleId = _authorizer.generateRoleId(module, role);
        vm.startPrank(module);
        if (!_authorizer.selfManagedModules(module)) {
            _authorizer.toggleModuleSelfManagement();
        }
        _authorizer.makeRoleTokenGatedFromModule(role);
        _authorizer.grantTokenRoleFromModule(role, address(token), threshold);
        vm.stopPrank();
        return roleId;
    }

    //function set up nftGated role
    function setUpNFTGatedRole(address module, uint8 role, address nft)
        internal
        returns (bytes32)
    {
        bytes32 roleId = _authorizer.generateRoleId(module, role);
        vm.startPrank(module);
        if (!_authorizer.selfManagedModules(module)) {
            _authorizer.toggleModuleSelfManagement();
        }
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
            address(mockModule),
            uint8(ModuleRoles.ROLE_TOKEN),
            address(roleToken),
            500
        );
        assertTrue(_authorizer.isTokenGated(roleId_1));

        bytes32 roleId_2 = setUpNFTGatedRole(
            address(mockModule), uint8(ModuleRoles.ROLE_NFT), address(roleNft)
        );
        assertTrue(_authorizer.isTokenGated(roleId_2));
    }

    // test admin setTokenGating
    function testSetTokenGatingByAdmin() public {
        // we set CLOE as admin
        makeAddressDefaultAdmin(CLOE);

        //we set and unset on an empty role

        // first we turn on self-management
        vm.prank(address(mockModule));
        _authorizer.toggleModuleSelfManagement();

        bytes32 roleId =
            _authorizer.generateRoleId(address(mockModule), uint8(0));

        //now we make it tokengated as admin
        vm.prank(CLOE);
        _authorizer.setTokenGated(roleId, true);

        assertTrue(_authorizer.isTokenGated(roleId));

        //and revert the change
        vm.prank(CLOE);
        _authorizer.setTokenGated(roleId, false);

        assertFalse(_authorizer.isTokenGated(roleId));
    }

    //test makeTokenGated fails if not empty
    function testMakingFunctionTokenGatedFailsIfAlreadyInUse() public {
        bytes32 roleId = _authorizer.generateRoleId(
            address(mockModule), uint8(ModuleRoles.ROLE_TOKEN)
        );

        //we switch on self-management and whitelist an address
        vm.startPrank(address(mockModule));
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_TOKEN), CLOE);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__RoleNotEmpty
                    .selector
            )
        );
        _authorizer.makeRoleTokenGatedFromModule(uint8(ModuleRoles.ROLE_TOKEN));
        assertFalse(_authorizer.isTokenGated(roleId));

        //we revoke the whitelist
        _authorizer.revokeRoleFromModule(uint8(ModuleRoles.ROLE_TOKEN), CLOE);

        // now it works:
        _authorizer.makeRoleTokenGatedFromModule(uint8(ModuleRoles.ROLE_TOKEN));
        assertTrue(_authorizer.isTokenGated(roleId));
    }
    // smae but with admin

    function testSetTokenGatedFailsIfRoleAlreadyInUse() public {
        // we set BOB as admin
        makeAddressDefaultAdmin(BOB);

        bytes32 roleId = _authorizer.generateRoleId(
            address(mockModule), uint8(ModuleRoles.ROLE_TOKEN)
        );

        //we switch on self-management and whitelist an address
        vm.prank(address(mockModule));
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_TOKEN), CLOE);

        vm.startPrank(BOB);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__RoleNotEmpty
                    .selector
            )
        );
        _authorizer.setTokenGated(roleId, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__RoleNotEmpty
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
            address(mockModule),
            uint8(ModuleRoles.ROLE_TOKEN),
            address(roleToken),
            500
        );
        setUpNFTGatedRole(
            address(mockModule), uint8(ModuleRoles.ROLE_NFT), address(roleNft)
        );
    }
    // -> no case

    function testCannotAddNonTokenWhenTokenGated() public {
        setUpTokenGatedRole(
            address(mockModule),
            uint8(ModuleRoles.ROLE_TOKEN),
            address(roleToken),
            500
        );

        vm.prank(address(mockModule));
        //First, the call to the interface reverts without reason
        vm.expectRevert();
        //Then the contract handles the reversion and sends the correct error message
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__InvalidToken
                    .selector,
                CLOE
            )
        );
        _authorizer.grantRoleFromModule(uint8(ModuleRoles.ROLE_TOKEN), CLOE);
    }

    function testAdminCannotAddNonTokenWhenTokenGated() public {
        // we set BOB as admin
        makeAddressDefaultAdmin(BOB);

        bytes32 roleId = setUpTokenGatedRole(
            address(mockModule),
            uint8(ModuleRoles.ROLE_TOKEN),
            address(roleToken),
            500
        );

        vm.prank(BOB);
        //First, the call to the interface reverts without reason
        vm.expectRevert();
        //Then the contract handles the reversion and sends the correct error message
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__InvalidToken
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
            address(mockModule),
            uint8(ModuleRoles.ROLE_TOKEN),
            address(roleToken),
            500
        );
        assertEq(_authorizer.getThresholdValue(roleId, address(roleToken)), 500);
    }

    // invalid threshold from module

    function testSetThresholdFailsIfInvalid() public {
        uint8 role = uint8(ModuleRoles.ROLE_TOKEN);
        vm.startPrank(address(mockModule));
        _authorizer.makeRoleTokenGatedFromModule(role);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__InvalidThreshold
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
            address(mockModule),
            uint8(ModuleRoles.ROLE_TOKEN),
            address(roleToken),
            500
        );

        // and we try to break it
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__InvalidThreshold
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
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__RoleNotTokenGated
                    .selector
            )
        );
        _authorizer.grantTokenRoleFromModule(
            uint8(ModuleRoles.ROLE_TOKEN), address(roleToken), 500
        );

        //also fails for the admin
        bytes32 roleId = _authorizer.generateRoleId(
            address(mockModule), uint8(ModuleRoles.ROLE_TOKEN)
        );

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenGatedRoleAuthorizer
                    .Module__TokenGatedRoleAuthorizer__RoleNotTokenGated
                    .selector
            )
        );
        _authorizer.setThreshold(roleId, address(roleToken), 500);
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
            address(mockModule),
            uint8(ModuleRoles.ROLE_TOKEN),
            address(roleToken),
            threshold
        );

        for (uint i = 0; i < callers.length; i++) {
            if (callers[i] == address(0)) {
                //cannot mint to 0 address
                continue;
            }

            roleToken.mint(callers[i], amounts[i]);

            //we ensure both ways to check give the same result
            vm.prank(address(mockModule));
            bool result = _authorizer.isAuthorized(
                uint8(ModuleRoles.ROLE_TOKEN), callers[i]
            );
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

        bytes32 roleId = setUpNFTGatedRole(
            address(mockModule), uint8(ModuleRoles.ROLE_NFT), address(roleNft)
        );

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
            bool result = _authorizer.isAuthorized(
                uint8(ModuleRoles.ROLE_NFT), callers[i]
            );
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
