// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";

interface IRoleAuthorizer is IAuthorizer {
    function toggleSelfManagement() external;
}
