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
import {FM_DepositVault_v1_Exposed} from
    "test/modules/fundingManager/depositVault/FM_DepositVault_v1_Exposed.sol";

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
    FM_DepositVault_v1_Exposed vault;
    ERC20PaymentClientBaseV1Mock client;

    uint internal constant BPS = 10_000;

    function setUp() public {
        address impl = address(new FM_DepositVault_v1_Exposed());
        vault = FM_DepositVault_v1_Exposed(Clones.clone(impl));

        _setUpOrchestrator(vault);

        // Init Module
        vault.init(_orchestrator, _METADATA, abi.encode(address(_token)));

        client = new ERC20PaymentClientBaseV1Mock();
        _addLogicModuleToOrchestrator(address(client));

        vm.prank(address(governor));
        feeManager.setMaxFee(feeManager.BPS());
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

    function testDeposit_Works(address user, uint amount, uint fee) public {
        vm.assume(
            user != address(0) && user != address(_token)
                && user != address(vault) && user != vault.trustedForwarder()
                && user != treasury
        );
        //Restrict to reasonable amounts
        amount = bound(amount, 1, type(uint128).max);
        fee = bound(fee, 0, BPS);

        // Setup
        _token.mint(user, amount);
        assertEq(_token.balanceOf(user), amount);
        vm.prank(user);
        _token.approve(address(vault), amount);

        if (fee != 0) {
            feeManager.setDefaultCollateralFee(fee);
        }

        //Expected Amounts
        uint expectedFeeAmount = amount * fee / BPS;
        uint expectedRestAmount = amount - expectedFeeAmount;

        // Deposit
        if (expectedFeeAmount != 0) {
            vm.expectEmit(true, true, true, true);
            emit IModule_v1.ProtocolFeeTransferred(
                address(_token),
                feeManager.getDefaultProtocolTreasury(),
                expectedFeeAmount
            );
        }
        vm.expectEmit(true, true, true, true);
        emit IFM_DepositVault_v1.Deposit(user, amount);
        vm.prank(user);
        vault.deposit(amount);

        // Assert balance
        assertEq(_token.balanceOf(address(vault)), expectedRestAmount);
        assertEq(_token.balanceOf(user), 0);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    function testTransferOrchestratorToken(address to, uint amount) public {
        vm.assume(to != address(0) && to != address(vault));

        _token.mint(address(vault), amount);

        vm.expectEmit(true, true, true, true);
        emit IFundingManager_v1.TransferOrchestratorToken(to, amount);

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

    //--------------------------------------------------------------------------
    // Internal Functions

    function testProcessProtocolFeeViaTransfer(address treasury, uint amount)
        public
    {
        vm.assume(treasury != address(0) && treasury != address(vault));
        amount = bound(amount, 1, type(uint).max);

        // Setup
        _token.mint(address(vault), amount);
        assertEq(_token.balanceOf(address(vault)), amount);

        vm.expectEmit(true, true, true, true);
        emit IModule_v1.ProtocolFeeTransferred(
            address(_token), treasury, amount
        );

        vault.exposed_processProtocolFeeViaTransfer(treasury, _token, amount);

        assertEq(_token.balanceOf(treasury), amount);
        assertEq(_token.balanceOf(address(vault)), 0);
    }

    function testProcessProtocolFeeViaTransferSkipsFeeCollectionIfFeeIsZero()
        public
    {
        // Setup
        _token.mint(address(vault), 1);
        assertEq(_token.balanceOf(address(vault)), 1);

        vault.exposed_processProtocolFeeViaTransfer(address(1), _token, 0);

        assertEq(_token.balanceOf(address(vault)), 1);
    }

    function testValidateRecipient(address receiver) public {
        if (receiver == address(0) || receiver == address(vault)) {
            vm.expectRevert(
                IFM_DepositVault_v1
                    .Module__DepositVault__InvalidRecipient
                    .selector
            );
        }
        vault.exposed_validateRecipient(receiver);
    }
}
