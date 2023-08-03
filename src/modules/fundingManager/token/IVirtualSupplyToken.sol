// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IVirtualSupplyToken {
    /// @notice Set virtual supply of token
    /// @param _newSupply The new virtual token supply
    function setVirtualSupply(uint _newSupply) external;

    /// @notice Return total amount of virtual supply
    function totalVirtualSupply() external returns (uint);
}
