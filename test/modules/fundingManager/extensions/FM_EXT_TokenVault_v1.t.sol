// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "forge-std/console.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import "@oz/utils/Strings.sol";

import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// SuT
import {
    FM_EXT_TokenVault_v1,
    IFM_EXT_TokenVault_v1
} from "@fm/extensions/FM_EXT_TokenVault_v1.sol";

import {Module_v1, IModule_v1} from "src/modules/base/Module_v1.sol";

import {
    IFundingManager_v1,
    FundingManagerV1Mock
} from "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

import {FM_EXT_TokenVault_v1_Exposed} from
    "test/modules/fundingManager/extensions/FM_EXT_TokenVault_v1_Exposed.sol";

contract FM_EXT_TokenVault_v1Test is ModuleTest {
    // SuT
    FM_EXT_TokenVault_v1_Exposed vault;

    function setUp() public virtual {
        // Add Module to Mock Orchestrator_v1
        address impl = address(new FM_EXT_TokenVault_v1_Exposed());
        vault = FM_EXT_TokenVault_v1_Exposed(Clones.clone(impl));

        _setUpOrchestrator(vault);

        vault.init(_orchestrator, _METADATA, bytes(""));
    }

    function testSupportsInterface() public {
        assertTrue(
            vault.supportsInterface(type(IFM_EXT_TokenVault_v1).interfaceId)
        );
    }

    // This function also tests all the getters
    function testInit() public override(ModuleTest) {}

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        vault.init(_orchestrator, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    //Modifier

    /* Test withdraw() function modifiers in place 
        ├── Given the caller is not the Orchestrator Admin
        │   └── And the modifier onlyOrchestratorAdmin is in position
        │       └── When the function withdraw() is called
        │           └── Then it should revert
        ├── Given the token address is invalid
        │   └── And the modifier validAddress(tok_) is in position
        │       └── When the function withdraw() is called
        │           └── Then it should revert
        ├── Given an invalid amount
        │   └── And the modifier validAmount(amt_) is in position
        │       └── When the function withdraw() is called
        │           └── Then it should revert
        └── Given the destination address is invalid
            └── And the modifier validAddress(dst_) is in position
                └── When the function withdraw() is called
                    └── Then it should revert
    */

    function testWithdraw_onlyOrchestratorAdminModifierInPosition() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                address(0)
            )
        );
        vm.prank(address(0));
        vault.withdraw(address(0), 0, address(0));
    }

    function testWithdraw_validAddressTokModifierInPosition() public {
        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        vault.withdraw(address(0), 1, address(1));
    }

    function testWithdraw_validAmountModifierInPosition() public {
        vm.expectRevert(
            IFM_EXT_TokenVault_v1
                .Module__FM_EXT_TokenVault__InvalidAmount
                .selector
        );
        vault.withdraw(address(_token), 0, address(1));
    }

    function testWithdraw_validAddressDstModifierInPosition() public {
        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        vault.withdraw(address(1), 1, address(0));
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    // @todo Add Gherkin
    /* Test withdraw() function
       └── Given token address is valid
           └── And the amount is valid
               └── And the destination address is valid
                   └── When the function withdraw() is called
                       └── Then it should transfer the tokens
                           └── And it should emit an event
    */

    function testWithdraw_worksGivenValidInputs(uint amount, address dst)
        public
    {
        vm.assume(amount > 0);
        vm.assume(dst != address(0) && dst != address(vault));

        // Setup
        _token.mint(address(vault), amount);

        // Test condition
        vm.expectEmit(true, true, true, true);
        emit IFM_EXT_TokenVault_v1.TokensWithdrawn(address(_token), dst, amount);
        vault.withdraw(address(_token), amount, dst);

        assertEq(_token.balanceOf(address(vault)), 0);
        assertEq(_token.balanceOf(dst), amount);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /*  Test internal _onlyValidAmount() function 
        # Given the amount is 0
        ## When the internal function _onlyValidAmount() is called
        ### Then it should revert
        # Given the amount is not 0
        ## When the internal function _onlyValidAmount() is called
        ### Then it should work
    */

    function testInternalOnlyValidAmount_revertGivenZeroAmount() public {
        vm.expectRevert(
            IFM_EXT_TokenVault_v1
                .Module__FM_EXT_TokenVault__InvalidAmount
                .selector
        );
        vault.exposed_onlyValidAmount(0);
    }

    function testInternalOnlyValidAmount_worksGivenNonZeroAmount(uint amount_)
        public
        view
    {
        vm.assume(amount_ != 0);
        vault.exposed_onlyValidAmount(amount_);
    }
}
