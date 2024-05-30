// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IFeeManager_v1} from "@ex/fees/interfaces/IFeeManager_v1.sol";

contract FeeManagerV1Mock is IFeeManager_v1 {
    function BPS() external returns (uint) {}

    //---------------------------
    // Treasuries

    function getDefaultProtocolTreasury() external view returns (address) {}

    function getWorkflowTreasuries(address workflow)
        external
        view
        returns (address)
    {}

    //---------------------------
    // Fees

    function getDefaultCollateralFee() external view returns (uint) {}

    function getDefaultIssuanceFee() external view returns (uint) {}

    function getCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee) {}

    function getIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee) {}

    function getCollateralWorkflowFeeAndTreasury(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee, address treasury) {}

    function getIssuanceWorkflowFeeAndTreasury(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee, address treasury) {}

    //--------------------------------------------------------------------------
    // Setter Functions

    //---------------------------
    // Treasuries

    function setDefaultProtocolTreasury(address _defaultProtocolTreasury)
        external
    {}

    function setWorkflowTreasury(address workflow, address treasury) external {}

    //---------------------------
    // Fees

    function setDefaultCollateralFee(uint _defaultCollateralFee) external {}

    function setDefaultIssuanceFee(uint _defaultIssuanceFee) external {}

    function setCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external {}

    function setIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external {}
}
