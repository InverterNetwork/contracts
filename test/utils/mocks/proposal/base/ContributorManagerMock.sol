// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {ContributorManager} from "src/proposal/base/ContributorManager.sol";

contract ContributorManagerMock is ContributorManager {
    function init() external initializer {
        __ContributorManager_init();
    }

    // Note that the `initializer` modifier is missing.
    function reinit() external {
        __ContributorManager_init();
    }
}
