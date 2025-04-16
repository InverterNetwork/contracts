// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Mocks
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

// SuT
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IFM_DepositVault_v1} from
    "@fm/depositVault/interfaces/IFM_DepositVault_v1.sol";
import {ERC20PaymentClientBaseV2Mock} from
    "@mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {FM_DepositVault_v1_Exposed} from
    "@mocks/modules/fundingManager/depositVault/FM_DepositVault_v1_Exposed.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "@unitTest/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "@testUtilities/OZErrors.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

contract FM_DepositVaultV1Test is ModuleTest {
    // SuT
    FM_DepositVault_v1_Exposed vault;
    ERC20PaymentClientBaseV2Mock client;

    uint internal constant BPS = 10_000;

    function setUp() public {
        address impl = address(new FM_DepositVault_v1_Exposed());
        vault = FM_DepositVault_v1_Exposed(Clones.clone(impl));

        _setUpOrchestrator(vault);

        // Init Module
        vault.init(_orchestrator, _METADATA, abi.encode(address(_token)));

        client = new ERC20PaymentClientBaseV2Mock();
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

    // -------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(vault.token()), address(_token));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        vault.init(_orchestrator, _METADATA, abi.encode());
    }

    // -------------------------------------------------------------------------
    // Tests: Public View Functions

    function testToken() public {
        assertEq(address(vault.token()), address(_token));
    }

    // -------------------------------------------------------------------------
    // Public Mutating Functions

    function testDeposit_Works(address user_, uint amount_, uint fee_) public {
        vm.assume(
            user_ != address(0) && user_ != address(_token)
                && user_ != address(vault) && user_ != vault.trustedForwarder()
                && user_ != treasury
        );
        //Restrict to_ reasonable amounts
        amount_ = bound(amount_, 1, type(uint128).max);
        fee_ = bound(fee_, 0, BPS);

        // Setup
        _token.mint(user_, amount_);
        assertEq(_token.balanceOf(user_), amount_);
        vm.prank(user_);
        _token.approve(address(vault), amount_);

        if (fee_ != 0) {
            feeManager.setDefaultCollateralFee(fee_);
        }

        //Expected Amounts
        uint expectedFeeAmount = amount_ * fee_ / BPS;
        uint expectedRestAmount = amount_ - expectedFeeAmount;

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
        emit IFM_DepositVault_v1.Deposit(user_, amount_);
        vm.prank(user_);
        vault.deposit(amount_);

        // Assert balance
        assertEq(_token.balanceOf(address(vault)), expectedRestAmount);
        assertEq(_token.balanceOf(user_), 0);
    }

    // -------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    function testTransferOrchestratorToken(address to_, uint amount_) public {
        vm.assume(to_ != address(0) && to_ != address(vault));

        _token.mint(address(vault), amount_);

        vm.expectEmit(true, true, true, true);
        emit IFundingManager_v1.TransferOrchestratorToken(to_, amount_);

        vm.prank(address(client));
        vault.transferOrchestratorToken(to_, amount_);

        assertEq(_token.balanceOf(to_), amount_);
        assertEq(_token.balanceOf(address(vault)), 0);
    }

    function testTransferOrchestratorTokenModifierInPosition() public {
        vm.expectRevert(IModule_v1.Module__OnlyCallableByPaymentClient.selector);
        vault.transferOrchestratorToken(address(this), 0);

        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        vm.prank(address(client));
        vault.transferOrchestratorToken(address(0), 0);
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    function testProcessProtocolFeeViaTransfer(address treasury_, uint amount_)
        public
    {
        vm.assume(treasury_ != address(0) && treasury_ != address(vault));
        amount_ = bound(amount_, 1, type(uint).max);

        // Setup
        _token.mint(address(vault), amount_);
        assertEq(_token.balanceOf(address(vault)), amount_);

        vm.expectEmit(true, true, true, true);
        emit IModule_v1.ProtocolFeeTransferred(
            address(_token), treasury_, amount_
        );

        vault.exposed_processProtocolFeeViaTransfer(treasury_, _token, amount_);

        assertEq(_token.balanceOf(treasury_), amount_);
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

    function testValidateRecipient(address receiver_) public {
        if (receiver_ == address(0) || receiver_ == address(vault)) {
            vm.expectRevert(
                IFM_DepositVault_v1
                    .Module__DepositVault__InvalidRecipient
                    .selector
            );
        }
        vault.exposed_validateRecipient(receiver_);
    }
}
