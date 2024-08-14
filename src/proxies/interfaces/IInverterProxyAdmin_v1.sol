// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IInverterTransparentUpgradeableProxy_v1} from
    "./IInverterTransparentUpgradeableProxy_v1.sol";

interface IInverterProxyAdmin_v1 {
    /// @notice Upgrades the corresponding proxy to the newest version of the implementation.
    /// @dev	This contract must be othe admin/owner of the proxy.
    /// @param proxy The proxy to upgrade.
    function upgradeToNewestVersion(
        IInverterTransparentUpgradeableProxy_v1 proxy
    ) external;

    /// @notice Upgrades multiple proxies to the newest version of the implementation.
    /// @dev	This contract must be othe admin/owner of the proxies.
    /// @param proxies The proxies to upgrade.
    function upgradeToNewestVersionBatched(
        IInverterTransparentUpgradeableProxy_v1[] calldata proxies
    ) external;
}
