// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";

import {
    RoleAuthorizer,
    IRoleAuthorizer
} from "src/modules/authorizer/RoleAuthorizer.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
// Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";
// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

contract RoleAuthorizerTest is Test {
    // Mocks
    RoleAuthorizer _authorizer;
    Proposal internal _proposal = new Proposal();
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    FundingManagerMock _fundingManager = new FundingManagerMock();
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();
    address ALBA = address(0xa1ba); //default authorized person
    // Proposal Constants
    uint internal constant _PROPOSAL_ID = 1;
    // Module Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public {
        address authImpl = address(new RoleAuthorizer());
        _authorizer = RoleAuthorizer(Clones.clone(authImpl));
        address propImpl = address(new Proposal());
        _proposal = Proposal(Clones.clone(propImpl));
        ModuleMock module = new  ModuleMock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        _proposal.init(
            _PROPOSAL_ID,
            address(this),
            _token,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor
        );

        address[] memory initialAuth = new address[](0);
        address initialManager = address(this);

        _authorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(initialAuth, initialManager)
        );
        assertEq(_authorizer.isAuthorized(1, address(this)), true);
        assertEq(_authorizer.isAuthorized(0, ALBA), false);
        assertEq(_authorizer.isAuthorized(0, address(this)), true);
    }

    //--------------------------------------------------------------------------------------
    // Tests taken from the ListAuthorizer

    function testInitWithInitialOwners(address[] memory initialAuth) public {
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        address authImpl = address(new RoleAuthorizer());
        RoleAuthorizer testAuthorizer = RoleAuthorizer(Clones.clone(authImpl));

        _validateAuthorizedList(initialAuth);

        testAuthorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );

        assertEq(address(testAuthorizer.proposal()), address(_proposal));

        for (uint i; i < initialAuth.length; ++i) {
            assertEq(testAuthorizer.isAuthorized(0, initialAuth[i]), true);
        }
        assertEq(testAuthorizer.isAuthorized(0, address(this)), false);
        bytes32 roleID = testAuthorizer.generateRoleId(address(_proposal), 0);
        assertEq(testAuthorizer.getRoleMemberCount(roleID), initialAuth.length);
    }

    function testReinitFails() public {
        //Create a mock new proposal
        Proposal newProposal = Proposal(Clones.clone(address(new Proposal())));

        address[] memory initialAuth = new address[](1);
        initialAuth[0] = address(this);

        vm.expectRevert();
        _authorizer.init(
            IProposal(newProposal), _METADATA, abi.encode(initialAuth)
        );
        assertEq(_authorizer.isAuthorized(0, address(this)), true);
        assertEq(address(_authorizer.proposal()), address(_proposal));
        assertEq(_authorizer.isAuthorized(0, ALBA), false);
        //assertEq(_authorizer.getAmountAuthorized(), 1);
    }

    // Test Register Roles
    // - Should revert if caller is not a module
    // - Should revert if roles for that interface already exist
    // - Should revert if calling Module does not implement interfaceId

    // Test grantRoleFromModule
    // - Should revert if caller is not a module
    // - Should revert if role does not exist
    // - Should not revert if role is already granted, but not emit events either

    // Test revokeRoleFromModule
    // - Should revert if caller is not a module
    // - Should revert if role does not exist
    // - SHOULD revert if target doesn't have role. (This is different from grantRoleFromModule)

    // Test getModuleRoleCount
    // - Should return 0 if no Module-specific roles exist
    // - Should correctly return the amount of Module-specific roles


    // =========================================================================
    // Test Helper Functions

    function _validateAuthorizedList(address[] memory auths)
        internal
        returns (address[] memory)
    {
        vm.assume(auths.length != 0);
        vm.assume(auths.length < 20);
        assumeValidAuths(auths);

        return auths;
    }
    // Adapted from proposal/helper/TypeSanityHelper.sol

    mapping(address => bool) authorizedCache;

    function assumeValidAuths(address[] memory addrs) public {
        for (uint i; i < addrs.length; ++i) {
            assumeValidAuth(addrs[i]);

            // Assume authorized address unique.
            vm.assume(!authorizedCache[addrs[i]]);

            // Add contributor address to cache.
            authorizedCache[addrs[i]] = true;
        }
    }

    function assumeValidAuth(address a) public view {
        address[] memory invalids = createInvalidAuthorized();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(a != invalids[i]);
        }
    }

    function createInvalidAuthorized() public view returns (address[] memory) {
        address[] memory invalids = new address[](7);

        invalids[0] = address(0);
        invalids[1] = address(_proposal);
        invalids[2] = address(_authorizer);
        invalids[3] = address(_paymentProcessor);
        invalids[4] = address(_token);
        invalids[5] = address(this);
        invalids[6] = ALBA;

        return invalids;
    }
    // =========================================================================
}
