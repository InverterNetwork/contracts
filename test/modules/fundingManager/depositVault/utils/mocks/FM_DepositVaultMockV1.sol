// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";

contract FM_DepositVaultMockV1 is FM_DepositVault_v1 {
    function call_deposit(address from, uint amount) external {
        _deposit(from, amount);
    }
}
