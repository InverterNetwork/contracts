// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ScriptConstants {
    ///////////////////////
    // Common Constants
    ///////////////////////
    bytes public emptyBytes = "0x0";
    address public bountyManagerAddress = 0x4FB5adc63fB08c7E7864Ce3f77714af6B8B50D9f;
    address public moduleFactoryAddress = 0x349D52589aF62Ba1b35DB871F54FA2c5aFcA6B5B;
    address public orchestratorAddress = 0x0A7c8C0EB1afAb6CBaD4bb2d4c738acFF047814A;
    address public receiptTokenAddress = 0xC0f1842627Eeda938911A9A8368407ec241AC1dd;

    ////////////////////////////////////////
    // Add Bounty Manager Claim Constants
    ////////////////////////////////////////
    address public addBountyManagerClaim_user1 = 0x9518a55e5cd4Ac650A37a6Ab6c352A3146D2C9BD;
    address public addBountyManagerClaim_user2 = 0x3064A400b5e74BeA12391058930EfD95a6911970;

    uint public addBountyManagerClaim_user1_amount = 100_000_000_000_000_000_000;
    uint public addBountyManagerClaim_user2_amount = 100_000_000_000_000_000_000;

    uint public orchestratorTokenDepositAmount = 10e18;
    uint public funder1TokenDepositAmount = 1000e18;
    uint public addBounty_minimumPayoutAmount = 100e18;
    uint public addBounty_maximumPayoutAmount = 250e18;
}