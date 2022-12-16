// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IRebasingERC20} from
    "@elastic-receipt-token/interfaces/_external/IRebasingERC20.sol";

interface IFundingManager is IRebasingERC20 {
    function deposit(uint amount) external;
    function depositFor(address to, uint amount) external;

    function withdraw(uint amount) external;
    function withdrawTo(address to, uint amount) external;
}
