// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// SuT
import {FundingVault} from "src/proposal/base/FundingVault.sol";

contract FundingVaultMock is FundingVault {
    function init(uint id, IERC20 token) external initializer {
        __FundingVault_init(id, IERC20MetadataUpgradeable(address(token)));
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(uint id, IERC20 token) external {
        __FundingVault_init(id, IERC20MetadataUpgradeable(address(token)));
    }
}
