// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {
    Initializable,
    IERC20MetadataUpgradeable,
    ERC4626Upgradeable
} from "@oz-up/token/ERC20/extensions/ERC4626Upgradeable.sol";

// Interfaces
//import {IFunderManager} from "src/proposal/base/IFunderManager.sol";

/**
 * @title
 *
 * @dev
 *
 * @author byterocket
 */
abstract contract FundingVault is ERC4626Upgradeable {
    function __FundingVault_init(IERC20MetadataUpgradeable token)
        internal
        onlyInitializing
    {
        __ERC4626_init(token);
    }
}
