// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// SuT
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

import {IFM_DepositVault_v1} from
    "@fm/depositVault/interfaces/IFM_DepositVault_v1.sol";

import {ERC20PaymentClientBaseV1Mock} from
    "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
import {FM_DepositVaultMockV1} from
    "test/modules/fundingManager/depositVault/utils/mocks/FM_DepositVaultMockV1.sol";

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
    FM_DepositVaultMockV1 vault;
    ERC20PaymentClientBaseV1Mock client;

    //--------------------------------------------------------------------------
    // Events

    event Deposit(address indexed _from, uint _amount);
    event TransferOrchestratorToken(address indexed _to, uint _amount);

    function setUp() public {
        address impl = address(new FM_DepositVaultMockV1());
        vault = FM_DepositVaultMockV1(Clones.clone(impl));

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

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    function testToken() public {
        assertEq(address(vault.token()), address(_token));
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    function testDeposit_Works(address user, uint amount) public {
        vm.assume(
            user != address(0) && user != address(_token)
                && user != address(vault) && user != vault.trustedForwarder()
        );

        // Setup
        _token.mint(user, amount);
        assertEq(_token.balanceOf(user), amount);
        vm.prank(user);
        _token.approve(address(vault), amount);

        // Deposit
        vm.prank(user);
        vault.deposit(amount);

        // Assert balance
        assertEq(_token.balanceOf(address(vault)), amount);
        assertEq(_token.balanceOf(user), 0);
    }

    function testDepositFor_Works(address from, address caller, uint amount)
        public
    {
        vm.assume(
            from != address(0) && from != address(_token)
                && from != address(vault) && from != vault.trustedForwarder()
                && from != caller
        );
        vm.assume(
            caller != address(0) && caller != address(_token)
                && caller != address(vault) && caller != vault.trustedForwarder()
                && from != caller
        );

        // Setup
        _token.mint(from, amount);
        assertEq(_token.balanceOf(from), amount);
        vm.prank(from);
        _token.approve(address(vault), amount);

        // Deposit
        vm.prank(caller);
        vault.depositFor(from, amount);

        // Assert balance
        assertEq(_token.balanceOf(address(vault)), amount);
        assertEq(_token.balanceOf(from), 0);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function testIntenalDeposit(address from, uint amount) public {
        vm.assume(
            from != address(0) && from != address(_token)
                && from != address(vault) && from != vault.trustedForwarder()
        );

        // Setup
        _token.mint(from, amount);
        assertEq(_token.balanceOf(from), amount);
        vm.prank(from);
        _token.approve(address(vault), amount);

        // Deposit and check for event
        vm.expectEmit(true, true, true, true);
        emit Deposit(from, amount);
        vault.call_deposit(from, amount);

        // Assert balance
        assertEq(_token.balanceOf(address(vault)), amount);
        assertEq(_token.balanceOf(from), 0);
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

        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        vm.prank(address(client));
        vault.transferOrchestratorToken(address(0), 0);
    }

    // =========================================================================
}
