// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.19;

interface IVirtualTokenSupply {
    error VirtualTokenSupply__SubtractResultsInUnderflow();
    error VirtualTokenSupply_AddResultsInOverflow();

    function setVirtualTokenSupply(uint _virtualSupply) external;
    function getVirtualTokenSupply() external view returns (uint);
}
