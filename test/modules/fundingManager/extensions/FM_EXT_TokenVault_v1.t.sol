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

contract FM_EXT_TokenVault_v1Test is ModuleTest {
    // SuT
    FM_EXT_TokenVault_v1 vault;

    function setUp() public virtual {
        // Add Module to Mock Orchestrator_v1
        address impl = address(new FM_EXT_TokenVault_v1());
        vault = FM_EXT_TokenVault_v1(Clones.clone(impl));

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

    function testValidAmount(uint amount) public {
        _token.mint(address(vault), amount);
        if (amount == 0) {
            vm.expectRevert(
                IFM_EXT_TokenVault_v1
                    .Module__FM_EXT_TokenVault__InvalidAmount
                    .selector
            );
        }

        vault.withdraw(address(_token), amount, address(1));
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    function testWithdraw(address token, uint amount, address dst) public {
        vm.assume(amount > 0);

        vm.assume(token != address(0) || token != address(vault));
        vm.assume(dst != address(0) || dst != address(vault));

        if (token == address(_token)) {
            _token.mint(address(vault), amount);
            vm.expectEmit(true, true, true, true);
            emit IFM_EXT_TokenVault_v1.TokensWithdrawn(token, dst, amount);
        } else {
            vm.expectRevert();
        }

        vault.withdraw(token, amount, dst);

        if (token == address(_token)) {
            assertEq(_token.balanceOf(address(vault)), 0);
            assertEq(_token.balanceOf(dst), amount);
        }
    }

    function testWithdrawModifierInPosition() public {
        // onlyOrchestratorAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                address(0)
            )
        );
        vm.prank(address(0));
        vault.withdraw(address(0), 0, address(0));

        //validAddress(tok)
        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        vault.withdraw(address(0), 1, address(1));

        //validAmount(amt)
        vm.expectRevert(
            IFM_EXT_TokenVault_v1
                .Module__FM_EXT_TokenVault__InvalidAmount
                .selector
        );
        vault.withdraw(address(1), 0, address(0));
        //validAddress(dst)
        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        vault.withdraw(address(1), 1, address(0));
    }
}
