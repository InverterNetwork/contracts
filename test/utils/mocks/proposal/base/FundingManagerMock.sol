// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {
    FundingManager,
    IFundingManager
} from "src/proposal/base/FundingManager.sol";

contract FundingManagerMock is FundingManager {
    IERC20 internal _token;

    function init(IERC20 token_, uint proposalId_, uint8 decimals_)
        external
        initializer
    {
        _token = token_;

        __FundingManager_init(proposalId_, decimals_);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(IERC20 token_, uint proposalId_, uint8 decimals_)
        external
    {
        _token = token_;

        __FundingManager_init(proposalId_, decimals_);
    }

    function token() public view override (FundingManager) returns (IERC20) {
        return _token;
    }
}
