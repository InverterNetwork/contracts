// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// SuT
import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

import {IFM_DepositVault_v1} from
    "@fm/depositVault/interfaces/IFM_DepositVault_v1.sol";

import {ERC20PaymentClientBaseV1Mock} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

contract FM_DepositVaultV1Test is ModuleTest {
    // SuT
    FM_DepositVault_v1 vault;
    ERC20PaymentClientBaseV1Mock client;

    //--------------------------------------------------------------------------
    // Events

    event Deposit(address indexed _from, uint _amount);
    event TransferOrchestratorToken(address indexed _to, uint _amount);

    function setUp() public {
        address impl = address(new FM_DepositVault_v1());
        vault = FM_DepositVault_v1(Clones.clone(impl));

        _setUpOrchestrator(vault);

        // Init Module
        vault.init(_orchestrator, _METADATA, abi.encode(address(_token)));

        client = new ERC20PaymentClientBaseV1Mock();
        _addLogicModuleToOrchestrator(address(client));
    }

    function testSupportsInterface() public {
        assertTrue(
            vault.supportsInterface(type(IFM_DepositVault_v1).interfaceId)
        );
        assertTrue(
            vault.supportsInterface(type(IFundingManager_v1).interfaceId)
        );
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(vault.token()), address(_token));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        vault.init(_orchestrator, _METADATA, abi.encode());
    }

    //--------------------------------------------------------------------------//
    // Tests:Modifiers

    function testValidAddress(address adr) public {
        if (adr == address(0) || adr == address(vault)) {
            vm.expectRevert(
                IFundingManager_v1
                    .Module__FundingManager__InvalidAddress
                    .selector
            );
        }
        vm.prank(address(client));
        vault.transferOrchestratorToken(adr, 0);
    }

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    function testToken() public {
        assertEq(address(vault.token()), address(_token));
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    function testDeposit(address user, uint amount) public {
        vm.assume(
            user != address(0) && user != address(_token)
                && user != address(vault) && user != vault.trustedForwarder()
        );

        _token.mint(user, amount);

        vm.prank(user);
        _token.approve(address(vault), amount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(user, amount);

        vm.prank(user);
        vault.deposit(amount);

        assertEq(_token.balanceOf(address(vault)), amount);
        assertEq(_token.balanceOf(user), 0);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    function testTransferOrchestratorToken(address to, uint amount) public {
        vm.assume(to != address(0) && to != address(vault));

        _token.mint(address(vault), amount);

        vm.expectEmit(true, true, true, true);
        emit TransferOrchestratorToken(to, amount);

        vm.prank(address(client));
        vault.transferOrchestratorToken(to, amount);

        assertEq(_token.balanceOf(to), amount);
        assertEq(_token.balanceOf(address(vault)), 0);
    }

    function testTransferOrchestratorTokenModifierInPosition() public {
        vm.expectRevert(IModule_v1.Module__OnlyCallableByPaymentClient.selector);
        vault.transferOrchestratorToken(address(this), 0);

        vm.expectRevert(
            IFundingManager_v1.Module__FundingManager__InvalidAddress.selector
        );
        vm.prank(address(client));
        vault.transferOrchestratorToken(address(0), 0);
    }

    // =========================================================================
}
