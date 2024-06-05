// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IInverterProxyAdmin_v1} from
    "src/proxies/interfaces/IInverterProxyAdmin_v1.sol";
import {IInverterTransparentUpgradeableProxy_v1} from
    "src/proxies/interfaces/IInverterTransparentUpgradeableProxy_v1.sol";

// External Dependencies
import {Ownable} from "@oz/access/Ownable.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

/**
 * @title   Inverter Proxy Admin
 *
 * @notice  Acts as the admin of the Inverter Transparent Upgradeable Proxies
 *          and is responsible for upgrading the proxies to the newest version.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 * @author  Inverter Network
 */
contract InverterProxyAdmin_v1 is Ownable2Step, IInverterProxyAdmin_v1 {
    //--------------------------------------------------------------------------
    // Constructor

    /// @notice Constructs the InverterProxyAdmin_v1.
    /// @param initialOwner The initial owner of the contract.
    constructor(address initialOwner) Ownable(initialOwner) {}

    //--------------------------------------------------------------------------
    // onlyOwner Mutating Functions

    /// @inheritdoc IInverterProxyAdmin_v1
    function upgradeToNewestVersion(
        IInverterTransparentUpgradeableProxy_v1 proxy
    ) external onlyOwner {
        proxy.upgradeToNewestVersion();
    }

    /// @inheritdoc IInverterProxyAdmin_v1
    function upgradeToNewestVersionBatched(
        IInverterTransparentUpgradeableProxy_v1[] calldata proxies
    ) external onlyOwner {
        for (uint i; i < proxies.length; ++i) {
            proxies[i].upgradeToNewestVersion();
        }
    }
}
