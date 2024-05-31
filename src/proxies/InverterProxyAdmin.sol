// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

//Internal Interfaces
import {IInverterTransparentUpgradeableProxy_v1} from
    "src/proxies/interfaces/IInverterTransparentUpgradeableProxy_v1.sol";

// External Dependencies
import {Ownable} from "@oz/access/Ownable.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

/**
 * @title   Inverter Proxy Admin
 *
 * @notice  Manages upgrades for Inverter Network proxies, allowing administrators to update
 *          the implementation logic of deployed contracts. Supports batch upgrades for multiple
 *          proxies in a single transaction.
 *
 * @author  Inverter Network
 */
contract InverterProxyAdmin_v1 is Ownable2Step {
    /**
     * @dev Sets the initial owner who can perform upgrades.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Upgrades the corresponding proxy to the newest version of the implementation.
    /// @dev This contract must be othe admin/owner of the proxy.
    /// @param proxy The proxy to upgrade.
    function upgradeToNewestVersion(
        IInverterTransparentUpgradeableProxy_v1 proxy
    ) external onlyOwner {
        proxy.upgradeToNewestVersion();
    }

    /// @notice Upgrades multiple proxies to the newest version of the implementation.
    /// @dev This contract must be othe admin/owner of the proxies.
    /// @param proxies The proxies to upgrade.
    function upgradeToNewestVersionBatched(
        IInverterTransparentUpgradeableProxy_v1[] calldata proxies
    ) external onlyOwner {
        for (uint i; i < proxies.length; i++) {
            proxies[i].upgradeToNewestVersion();
        }
    }
}
