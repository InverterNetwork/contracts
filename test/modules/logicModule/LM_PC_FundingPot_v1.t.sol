// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {LM_PC_FundingPot_v1_Exposed} from
    "test/modules/logicModule/LM_PC_FundingPot_v1_Exposed.sol";
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// System under Test (SuT)
import {
    LM_PC_FundingPot_v1,
    ILM_PC_FundingPot_v1
} from "src/modules/logicModule/LM_PC_FundingPot_v1.sol";

contract LM_PC_FundingPot_v1Test is ModuleTest {
    // =========================================================================
    // State

    // SuT
    LM_PC_FundingPot_v1_Exposed fundingPot;

    // Mocks
    ERC20Mock paymentToken;

    // Variables
    address orchestratorAdmin = makeAddr("orchestratorAdmin");

    // =========================================================================
    // Setup

    function setUp() public {
        // Deploy the SuT
        address impl = address(new LM_PC_FundingPot_v1_Exposed());
        fundingPot = LM_PC_FundingPot_v1_Exposed(Clones.clone(impl));

        // Setup the module to test
        _setUpOrchestrator(fundingPot);
        _authorizer.grantRole(_authorizer.getAdminRole(), orchestratorAdmin);

        // Initiate the Logic Module with the metadata and config data
        fundingPot.init(_orchestrator, _METADATA, abi.encode(""));
    }

    // =========================================================================
    // Test: Initialization

    // Test if the orchestrator is correctly set
    function testInit() public override(ModuleTest) {
        assertEq(address(fundingPot.orchestrator()), address(_orchestrator));
    }

    // Test the interface support
    function testSupportsInterface() public {
        assertTrue(
            fundingPot.supportsInterface(
                type(IERC20PaymentClientBase_v2).interfaceId
            )
        );
        assertTrue(
            fundingPot.supportsInterface(type(ILM_PC_FundingPot_v1).interfaceId)
        );
    }

    // Test the reinit function
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingPot.init(_orchestrator, _METADATA, abi.encode(""));
    }

    /* Test external grantFundingPotAdminRole()
        ├── Given an address has the orchestrator admin role
        │   └── When granting the funding pot admin role
        │       └── Then it should be granted
    */
    function testFuzz_GrantFundingPotAdminRole(address admin_) public {
        _assumeValidFundingPotAdmin(admin_);

        vm.startPrank(orchestratorAdmin);
        fundingPot.grantFundingPotAdminRole(admin_);

        assertEq(
            _authorizer.hasRole(
                _authorizer.generateRoleId(
                    address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
                ),
                admin_
            ),
            true
        );
        vm.stopPrank();
    }

    /* Test external grantFundingPotAdminRole()
        ├── Given an address already has the funding pot admin role
        │   └── When granting the funding pot admin role
        │       └── Then it should revert with FundingPotAdminAlreadySet
    */
    function testFuzz_GrantFundingPotAdminRole_failsWhenGrantedTwice(
        address admin_
    ) public {
        _assumeValidFundingPotAdmin(admin_);

        vm.startPrank(orchestratorAdmin);
        fundingPot.grantFundingPotAdminRole(admin_);

        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot_FundingPotAdminAlreadySet
                .selector
        );
        fundingPot.grantFundingPotAdminRole(admin_);
        vm.stopPrank();
    }

    /* Test external grantFundingPotAdminRole()
        ├── Given an address doesn't have the orchestrator admin role
        │   └── When granting the funding pot admin role
        │       └── Then it should revert with CallerNotAuthorized
    */
    function testFuzz_GrantFundingPotAdminRole_failsWhenNotOrchestratorAdmin(
        address caller_,
        address admin_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != orchestratorAdmin);
        _assumeValidFundingPotAdmin(admin_);

        vm.startPrank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _orchestrator.authorizer().getAdminRole(),
                caller_
            )
        );
        fundingPot.grantFundingPotAdminRole(admin_);
        vm.stopPrank();
    }

    /* Test external revokeFundingPotAdminRole()
        ├── Given an address has the funding pot admin role
        │   └── When revoking the funding pot admin role
        │       └── Then it should be revoked
    */
    function testFuzz_RevokeFundingPotAdminRole(address admin_) public {
        testFuzz_GrantFundingPotAdminRole(admin_);

        vm.startPrank(orchestratorAdmin);
        fundingPot.revokeFundingPotAdminRole(admin_);
        vm.stopPrank();

        assertEq(
            _authorizer.hasRole(fundingPot.getFundingPotAdminRoleId(), admin_),
            false
        );
    }

    /* Test external revokeFundingPotAdminRole()
        ├── Given an address doesn't have the funding pot admin role
        │   └── When revoking the funding pot admin role
        │       └── Then it should revert with CallerNotAuthorized
    */
    function testFuzz_RevokeFundingPotAdminRole_failsWhenNotFundingPotAdmin(
        address caller_,
        address admin_
    ) public {
        _assumeValidFundingPotAdmin(admin_);
        testFuzz_GrantFundingPotAdminRole(admin_);

        vm.startPrank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _orchestrator.authorizer().getAdminRole(),
                caller_
            )
        );
        fundingPot.revokeFundingPotAdminRole(admin_);
        vm.stopPrank();
    }

    // =========================================================================
    // Test exposed_ functions

    function testFuzz_exposed_checkForFundingPotAdminRole(address admin_)
        public
    {
        assertEq(fundingPot.exposed_checkForFundingPotAdminRole(admin_), false);

        vm.startPrank(orchestratorAdmin);
        fundingPot.grantFundingPotAdminRole(admin_);
        vm.stopPrank();

        assertEq(fundingPot.exposed_checkForFundingPotAdminRole(admin_), true);
    }

    // =========================================================================
    // Helper functions

    function _assumeValidFundingPotAdmin(address admin_) internal {
        vm.assume(
            admin_ != address(0) && admin_ != orchestratorAdmin
                && admin_ != address(fundingPot) && admin_ != address(this)
        );
    }
}
