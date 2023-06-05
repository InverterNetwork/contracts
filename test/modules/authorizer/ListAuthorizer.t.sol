// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    ListAuthorizer,
    IAuthorizer
} from "src/modules/authorizer/ListAuthorizer.sol";

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

contract ListAuthorizerTest is Test {
    // Mocks
    ListAuthorizer _authorizer;
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
        address authImpl = address(new ListAuthorizer());
        _authorizer = ListAuthorizer(Clones.clone(authImpl));

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

        address[] memory initialAuth = new address[](1);
        initialAuth[0] = address(this);

        _authorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );

        //authorize one address and deauthorize the initializer.
        _authorizer.addToAuthorized(ALBA);
        _authorizer.removeFromAuthorized(address(this));

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(_authorizer.getAmountAuthorized(), 1);
    }

    function testInitWithInitialAuthorized(address[] memory initialAuth)
        public
    {
        //Checks that address list gets correctly stored on initialization
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        address authImpl = address(new ListAuthorizer());
        ListAuthorizer testAuthorizer = ListAuthorizer(Clones.clone(authImpl));

        _validateAuthorizedList(initialAuth);

        testAuthorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );

        assertEq(address(testAuthorizer.proposal()), address(_proposal));

        for (uint i; i < initialAuth.length; ++i) {
            assertEq(testAuthorizer.isAuthorized(initialAuth[i]), true);
        }
        assertEq(testAuthorizer.isAuthorized(address(this)), false);
        assertEq(testAuthorizer.getAmountAuthorized(), initialAuth.length);
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
        assertEq(_authorizer.isAuthorized(address(this)), false);
        assertEq(address(_authorizer.proposal()), address(_proposal));
        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.getAmountAuthorized(), 1);
    }

    function testInitWithEmptyInitialAuthorizedFails() public {
        // We "reuse" the proposal created in the setup, but the proposal doesn't know about this new authorizer.

        address authImpl = address(new ListAuthorizer());
        ListAuthorizer testAuthorizer = ListAuthorizer(Clones.clone(authImpl));

        address[] memory initialAuth;
        vm.expectRevert(
            abi.encodeWithSelector(
                ListAuthorizer
                    .Module__ListAuthorizer__invalidInitialAuthorizers
                    .selector
            )
        );
        testAuthorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );

        //test faulty list (zero addresses)
        initialAuth = new address[](2);

        vm.expectRevert(
            abi.encodeWithSelector(
                ListAuthorizer
                    .Module__ListAuthorizer__invalidInitialAuthorizers
                    .selector
            )
        );
        testAuthorizer.init(
            IProposal(_proposal), _METADATA, abi.encode(initialAuth)
        );
        assertEq(address(testAuthorizer.proposal()), address(0));
        assertEq(testAuthorizer.getAmountAuthorized(), 0);
    }

    function testAddAuthorized(address[] memory newAuthorized) public {
        uint amountAuth = _authorizer.getAmountAuthorized();

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.addToAuthorized(newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(_authorizer.isAuthorized(newAuthorized[i]), true);
        }
        assertEq(
            _authorizer.getAmountAuthorized(),
            (amountAuth + newAuthorized.length)
        );
    }

    function testRemoveLastAuthorizedFails() public {
        uint amountAuth = _authorizer.getAmountAuthorized();

        vm.expectRevert(
            abi.encodeWithSelector(
                ListAuthorizer
                    .Module__ListAuthorizer__AuthorizerListCannotBeEmpty
                    .selector
            )
        );

        vm.prank(address(ALBA));
        _authorizer.removeFromAuthorized(ALBA);

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.getAmountAuthorized(), amountAuth);
    }

    function testRemoveAuthorized(address[] memory newAuthorized) public {
        uint amountAuth = _authorizer.getAmountAuthorized();

        _validateAuthorizedList(newAuthorized);

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.addToAuthorized(newAuthorized[i]);
        }
        vm.stopPrank();

        vm.startPrank(address(ALBA));
        for (uint i; i < newAuthorized.length; ++i) {
            _authorizer.removeFromAuthorized(newAuthorized[i]);
        }
        vm.stopPrank();

        for (uint i; i < newAuthorized.length; ++i) {
            assertEq(_authorizer.isAuthorized(newAuthorized[i]), false);
        }

        assertEq(_authorizer.isAuthorized(ALBA), true);
        assertEq(_authorizer.getAmountAuthorized(), amountAuth);
    }

    function testTransferAuthorization(address[] memory authList) public {
        _validateAuthorizedList(authList);

        uint amountAuth = _authorizer.getAmountAuthorized();

        //transfers authorization to the next one on the list
        for (uint i; i < authList.length; ++i) {
            if (i % 2 == 0) {
                vm.prank(ALBA);
                _authorizer.addToAuthorized(authList[i]);
            } else {
                vm.prank(authList[i - 1]);
                _authorizer.transferAuthorization(authList[i]);
            }
        }

        for (uint i = 1; i < authList.length; i += 2) {
            assertEq(_authorizer.isAuthorized(authList[i - 1]), false);
            assertEq(_authorizer.isAuthorized(authList[i]), true);
        }
        assertEq(
            _authorizer.getAmountAuthorized(),
            (amountAuth + (authList.length / 2) + (authList.length % 2))
        );
    }

    function testTransferAuthorizationToAlreadyAuthorizedFails(
        address[] memory authList
    ) public {
        _validateAuthorizedList(authList);

        for (uint i; i < authList.length; ++i) {
            vm.prank(ALBA);
            _authorizer.addToAuthorized(authList[i]);
        }
        uint amountAuth = _authorizer.getAmountAuthorized();

        for (uint i = 1; i < authList.length; ++i) {
            vm.prank(authList[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ListAuthorizer
                        .Module__ListAuthorizer__InvalidAuthorizationTransfer
                        .selector
                )
            );
            _authorizer.transferAuthorization(authList[i - 1]);
        }

        for (uint i = 1; i < authList.length; ++i) {
            assertEq(_authorizer.isAuthorized(authList[i]), true);
        }
        assertEq(_authorizer.getAmountAuthorized(), amountAuth);
    }

    function testUnauthorizedCallsFail(address[] memory nonAuthUsers) public {
        _validateAuthorizedList(nonAuthUsers);

        for (uint i; i < nonAuthUsers.length; ++i) {
            //test if a non authorized address, fails authorization
            address ATTACKER = nonAuthUsers[i];
            assertEq(_authorizer.isAuthorized(ATTACKER), false);

            //add without authorization fails
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(address(ATTACKER));
            _authorizer.addToAuthorized(ATTACKER);

            //remove without authorization fails
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(address(ATTACKER));
            _authorizer.removeFromAuthorized(ATTACKER);

            //transfer withour authorization fails
            vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
            vm.prank(address(ATTACKER));
            _authorizer.removeFromAuthorized(address(1337));
        }
    }

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
