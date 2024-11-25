// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IGovernor_v1} from "@ex/governance/interfaces/IGovernor_v1.sol";
import {IFeeManager_v1} from "@ex/fees/interfaces/IFeeManager_v1.sol";

import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleFactory_v1} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

contract GovernorV1Mock is IGovernor_v1 {
    address feeManager;

    uint public howManyCalls;
    //--------------------------------------------------------------------------
    // Initialization

    function init(address, address, uint, address, address) external {}

    function moduleFactoryInitCallback(IInverterBeacon_v1[] calldata)
        external
    {
        howManyCalls++;
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    function getBeaconTimelock(address)
        external
        view
        returns (Timelock memory)
    {}

    function getLinkedBeacons()
        external
        view
        returns (IInverterBeacon_v1[] memory)
    {}

    //--------------------------------------------------------------------------
    // FeeManager

    function getFeeManager() external view returns (address) {
        return feeManager;
    }

    function setFeeManager(address newFeeManager) external {
        feeManager = newFeeManager;
    }

    function getModuleFactory() external pure returns (address) {
        return address(0);
    }

    function setModuleFactory(address) external {}

    function setFeeManagerMaxFee(uint) external {}

    function setFeeManagerDefaultProtocolTreasury(address) external {}

    function setFeeManagerWorkflowTreasuries(address workflow, address treasury)
        external
    {
        IFeeManager_v1(feeManager).setWorkflowTreasury(workflow, treasury);
    }

    function setFeeManagerDefaultCollateralFee(uint) external {}

    function setFeeManagerDefaultIssuanceFee(uint) external {}

    function setFeeManagerCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external {
        IFeeManager_v1(feeManager).setCollateralWorkflowFee(
            workflow, module, functionSelector, set, fee
        );
    }

    function setFeeManagerIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external {
        IFeeManager_v1(feeManager).setIssuanceWorkflowFee(
            workflow, module, functionSelector, set, fee
        );
    }

    //--------------------------------------------------------------------------
    // Factory Functions

    function registerMetadataInModuleFactory(
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external {}

    function registerNonModuleBeacon(IInverterBeacon_v1 beacon) external {}

    //--------------------------------------------------------------------------
    // Beacon Functions

    //---------------------------
    // Upgrade

    function upgradeBeaconWithTimelock(
        address beacon,
        address newImplementation,
        uint newMinorVersion,
        uint newPatchVersion
    ) external {}

    function triggerUpgradeBeaconWithTimelock(address) external {}

    function cancelUpgrade(address) external {}

    function setTimelockPeriod(uint) external {}

    //---------------------------
    // Emergency Shutdown

    function initiateBeaconShutdown(address) external {}
    function initiateBeaconShutdownForAllLinkedBeacons() external {}

    function forceUpgradeBeaconAndRestartImplementation(
        address,
        address,
        uint,
        uint
    ) external {}

    function restartBeaconImplementation(address) external {}
    //---------------------------
    // Ownable2Step

    function acceptOwnership(address) external {}
}
