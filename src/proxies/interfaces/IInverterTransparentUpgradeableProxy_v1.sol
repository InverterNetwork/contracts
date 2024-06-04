// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC1967} from "@oz/interfaces/IERC1967.sol";

interface IInverterTransparentUpgradeableProxy_v1 is IERC1967 {
    function upgradeToNewestVersion() external;
}
