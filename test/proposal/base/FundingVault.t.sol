// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// SuT
import {FundingVaultMock} from
    "test/utils/mocks/proposal/base/FundingVaultMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mock Dependencies
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract FundingVaultTest is Test {
    // SuT
    FundingVaultMock fundingVault;

    // Mocks
    IERC20 token;

    function setUp() public {
        token = new ERC20Mock("Token Mock", "TKNM");

        fundingVault = new FundingVaultMock();
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public {
        fundingVault.init(1, token);

        // Check that proposal's dependencies correctly initialized.
        // ERC20: Name and symbol set correctly.
        assertEq(fundingVault.name(), "Inverter Funding Token - Proposal #1");
        assertEq(fundingVault.symbol(), "IFT-1");
        // ERC4626: Asset should be set as token's address.
        assertEq(fundingVault.asset(), address(token));
    }

    function testReinitFails() public {
        fundingVault.init(1, token);

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        fundingVault.init(1, token);
    }

    function testInitFailsForNonInitializerFunction() public {
        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        fundingVault.initNoInitializer(1, token);
    }
}
