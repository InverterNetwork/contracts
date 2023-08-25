// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.19;

interface IVirtualCollateralSupply {
    error VirtualCollateralSupply__SubtractResultsInUnderflow();
    error VirtualCollateralSupply_AddResultsInOverflow();

    function setVirtualCollateralSupply(uint _virtualSupply) external;
    function getVirtualCollateralSupply() external view returns (uint);
}
