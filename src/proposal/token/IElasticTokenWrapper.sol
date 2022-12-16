// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IElasticTokenWrapper is IERC20 {
    error ElasticTokenWrapper__TotalSupplyOfUnderlierIsZero();

    function depositFor(address to, uint uAmount) external returns (uint);
    function burnTo(address to, uint amount) external returns (uint);
}
