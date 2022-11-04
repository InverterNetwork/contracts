// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    ContributorManager,
    IContributorManager
} from "src/proposal/base/ContributorManager.sol";

contract ContributorManagerMock is ContributorManager {
    mapping(address => bool) private _authorized;

    bool private _allAuthorized;

    function __ContributorManager_setIsAuthorized(address who, bool to)
        external
    {
        _authorized[who] = to;
    }

    function __ContributorManager_setAllAuthorized(bool to) external {
        _allAuthorized = to;
    }

    function init() external initializer {
        __ContributorManager_init();
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer() external {
        __ContributorManager_init();
    }

    function __ContributorManager_isAuthorized(address who)
        internal
        view
        override (ContributorManager)
        returns (bool)
    {
        return _authorized[who] || _allAuthorized;
    }
}
