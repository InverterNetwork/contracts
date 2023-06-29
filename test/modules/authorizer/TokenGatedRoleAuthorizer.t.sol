// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Test} from "forge-std/Test.sol";

import {RoleAuthorizerTest} from "test/modules/authorizer/RoleAuthorizer.t.sol";

// SuT
import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";

import {
    RoleAuthorizer,
    IRoleAuthorizer
} from "src/modules/authorizer/RoleAuthorizer.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";
// Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";
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
        initialAuth[0] = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(initialAuth, initialManager)
        );
        assertEq(
            _authorizer.hasRole(
                _authorizer.PROPOSAL_MANAGER_ROLE(), address(this)
            ),
            true
        );
        assertEq(
            _authorizer.hasRole(_authorizer.PROPOSAL_OWNER_ROLE(), ALBA), true
        );
        assertEq(
            _authorizer.hasRole(
                _authorizer.PROPOSAL_OWNER_ROLE(), address(this)
            ),
            false
        );
    }
}

contract TokenGatedRoleAuthorizerTest is Test {
    // Mocks
    TokenGatedRoleAuthorizer _authorizer;
    Proposal internal _proposal = new Proposal();
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
        address authImpl = address(new TokenGatedRoleAuthorizer());
        _authorizer = TokenGatedRoleAuthorizer(Clones.clone(authImpl));
        address propImpl = address(new Proposal());
        _proposal = Proposal(Clones.clone(propImpl));
        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);
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
        initialAuth[0] = ALBA;
        address initialManager = address(this);

        _authorizer.init(
            IProposal(_proposal),
            _METADATA,
            abi.encode(initialAuth, initialManager)
        );
        assertEq(
            _authorizer.hasRole(
                _authorizer.PROPOSAL_MANAGER_ROLE(), address(this)
            ),
            true
        );
        assertEq(
            _authorizer.hasRole(_authorizer.PROPOSAL_OWNER_ROLE(), ALBA), true
        );
        assertEq(
            _authorizer.hasRole(
                _authorizer.PROPOSAL_OWNER_ROLE(), address(this)
            ),
            false
        );

        //We mint some tokens: First, two different amounts of ERC20
        roleToken.mint(BOB, 1000);
        roleToken.mint(CLOE, 10);

        //Then, a ERC721 for BOB
        roleNft.mint(BOB);
    }

    // function set up tokenGated role with threshold
    function setUpTokenGatedRole(
        address module,
        uint8 role,
        address token,
        uint threshold
    ) {
        vm.startPrank(module);
        _authorizer.toggleSelfManagement();
        _authorizer.makeRoleTokenGatedFromModule(role);
        _authorizer.grantTokenRoleFromModule(role, address(token), threshold);
        vm.stopPrank();
    }

    //function set up nftGated role
    function setUpNFTGatedRole(address module, uint8 role, address nft) {
        vm.startPrank(module);
        _authorizer.toggleSelfManagement();
        _authorizer.makeRoleTokenGatedFromModule(role);
        _authorizer.grantTokenRoleFromModule(role, address(nft), 0);
        vm.stopPrank();
    }

    // -------------------------------------
    // State change and validation tests

    //test make role token gated

    // test admin setTokenGating

    // test if admin can still change state if role tokengated

    // test interface enforcement when granting role
    // -> yes case
    // -> no case

    // Check setting the threshold

    //Test Authorization

    // Test token authorization
    // -> yes case
    // -> tokens below threshold
    // -> no tokens

    // Test NFT authorization
    // -> yes case
    // -> no case
}
