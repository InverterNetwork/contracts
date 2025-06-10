// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {TokenInterface} from "@aut/role/AUT_TokenGated_Roles_v1.sol";

contract TokenInterfaceMock is TokenInterface {
    //==========================================================================
    // Storage
    mapping(address => uint) public tokenBalances;

    //==========================================================================
    // Public Getter Functions

    function balanceOf(address _owner) external view returns (uint balance) {
        return tokenBalances[_owner];
    }

    //==========================================================================
    // Public Setter Functions

    function setTokenBalance(address _owner, uint _balance) external {
        tokenBalances[_owner] = _balance;
    }
}
