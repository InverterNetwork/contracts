// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IGovernor_v1} from "@ex/governance/interfaces/IGovernor_v1.sol";

contract GovernorV1Mock is IGovernor_v1 {
    address feeManager;
    //--------------------------------------------------------------------------
    // Initialization

    function init(address, address, uint) external {}

    //--------------------------------------------------------------------------
    // Getter Functions

    function getBeaconTimelock(address) external returns (Timelock memory) {}

    //--------------------------------------------------------------------------
    // FeeManager

    function getFeeManager() external view returns (address) {
        return feeManager;
    }

    function setFeeManager(address newFeeManager) external {
        feeManager = newFeeManager;
    }

    function setFeeManagerDefaultProtocolTreasury(address) external {}

    function setFeeManagerWorkflowTreasuries(address, address) external {}

    function setFeeManagerDefaultCollateralFee(uint) external {}

    function setFeeManagerDefaultIssuanceFee(uint) external {}

    function setFeeManagerCollateralWorkflowFee(
        address,
        address,
        bytes4,
        bool,
        uint
    ) external {}

    function setFeeManagerIssuanceWorkflowFee(
        address,
        address,
        bytes4,
        bool,
        uint
    ) external {}

    //--------------------------------------------------------------------------
    // Beacon Functions

    //---------------------------
    //Upgrade

    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion
    ) external {}

    function triggerUpgradeBeaconWithTimelock(address) external {}

    function cancelUpgrade(address) external {}

    function setTimelockPeriod(uint) external {}

    //---------------------------
    //Emergency Shutdown

    function initiateBeaconShutdown(address) external {}

    function forceUpgradeBeaconAndRestartImplementation(address, address, uint)
        external
    {}

    function restartBeaconImplementation(address) external {}
    //---------------------------
    //Ownable2Step

    function acceptOwnership(address) external {}
}
