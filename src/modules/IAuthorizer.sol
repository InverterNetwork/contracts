// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

interface IAuthorizer {
    function isAuthorized(address who) external view returns (bool);
}
