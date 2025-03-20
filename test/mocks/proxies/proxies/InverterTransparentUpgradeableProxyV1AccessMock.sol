pragma solidity ^0.8.0;

import {InverterTransparentUpgradeableProxy_v1} from
    "src/proxies/InverterTransparentUpgradeableProxy_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

contract InverterTransparentUpgradeableProxyV1AccessMock is
    InverterTransparentUpgradeableProxy_v1
{
    bool public upgradeToNewestVersionActive = true;
    uint public upgradeToNewestVersionCalledCounter;

    function flipUpgradeToNewestVersionActive() external view {
        upgradeToNewestVersionActive != upgradeToNewestVersionActive;
    }

    constructor(
        IInverterBeacon_v1 beacon,
        address initialOwner,
        bytes memory _data
    ) InverterTransparentUpgradeableProxy_v1(beacon, initialOwner, _data) {}

    function direct__admin() external view returns (address) {
        return _admin;
    }

    function direct__beacon() external view returns (address) {
        return address(_beacon);
    }

    function direct__implementation() external view returns (address) {
        return _implementation();
    }

    function direct_upgradeToNewestVersion() external {
        upgradeToNewestVersion();
    }

    function upgradeToNewestVersion() internal override {
        upgradeToNewestVersionCalledCounter++;
        if (upgradeToNewestVersionActive) super.upgradeToNewestVersion();
    }
}
