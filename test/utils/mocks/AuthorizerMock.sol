// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";

import {IAuthorizer} from "src/modules/IAuthorizer.sol";

contract AuthorizerMock is IAuthorizer, ModuleMock {
    mapping(address => bool) private _authorized;

    bool private _allAuthorized;

    function setIsAuthorized(address who, bool to) external {
        _authorized[who] = to;
    }

    function setAllAuthorized(bool to) external {
        _allAuthorized = to;
    }

    //--------------------------------------------------------------------------
    // IAuthorizer Functions

    function isAuthorized(address who) external view returns (bool) {
        return _authorized[who] || _allAuthorized;
    }
}
