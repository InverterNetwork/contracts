// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IGovernor} from "src/external/governance/IGovernor.sol";

contract GovernorMock is IGovernor {
    address feeManager;
    //--------------------------------------------------------------------------
    // Initialization

    function init(
        address communityMultisig,
        address teamMultisig,
        uint timelockPeriod
    ) external {}

    //--------------------------------------------------------------------------
    // Getter Functions

    function getBeaconTimelock(address beacon)
        external
        returns (Timelock memory)
    {}

    //--------------------------------------------------------------------------
    // FeeManager

    function getFeeManager() external view returns (address) {
        return feeManager;
    }

    function setFeeManager(address newFeeManager) external {
        feeManager = newFeeManager;
    }

    //--------------------------------------------------------------------------
    // Beacon Functions

    //---------------------------
    //Upgrade

    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    ) external {}

    function triggerUpgradeBeaconWithTimelock(address beacon) external {}

    function cancelUpgrade(address beacon) external {}

    function setTimelockPeriod(uint newtimelockPeriod) external {}

    //---------------------------
    //Emergency Shutdown

    function initiateBeaconShutdown(address beacon) external {}

    function forceUpgradeBeaconAndRestartImplementation(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    ) external {}

    function restartBeaconImplementation(address beacon) external {}
    //---------------------------
    //Ownable2Step

    function acceptOwnership(address adr) external {}
}
