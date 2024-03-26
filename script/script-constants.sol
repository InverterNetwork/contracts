// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ScriptConstants {
    ///////////////////////
    // Common Constants
    ///////////////////////
    bytes public emptyBytes = "0x0";
    address public bountyManagerAddress =
        0x3F65847e68EB9fa561238BC4416f8766322c13eD;
    address public moduleFactoryAddress =
        0xc8DAAbCc110F1271967aFd450B45d308A9B72Ff2;
    address public orchestratorAddress =
        0x1c9373fae3bB828f3cb9001326415A3dBe5cCd0C;
    address public receiptTokenAddress =
        0x94A988C49a84b990bc1750bC516b4EE63327442c;

    ////////////////////////////////////////
    // Add Bounty Manager Claim Constants
    ////////////////////////////////////////
    address public addBountyManagerClaim_user1 =
        0x9518a55e5cd4Ac650A37a6Ab6c352A3146D2C9BD;
    address public addBountyManagerClaim_user2 =
        0x3064A400b5e74BeA12391058930EfD95a6911970;

    uint public addBountyManagerClaim_user1_amount = 100_000_000_000_000_000_000;
    uint public addBountyManagerClaim_user2_amount = 100_000_000_000_000_000_000;

    uint public orchestratorTokenDepositAmount = 10e18;
    uint public funder1TokenDepositAmount = 1000e18;
    uint public addBounty_minimumPayoutAmount = 100e18;
    uint public addBounty_maximumPayoutAmount = 250e18;
}
