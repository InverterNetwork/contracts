// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Module, IModule, IProposal} from "src/modules/base/Module.sol";
import {
    FundingManager,
    IFundingManager
} from "src/modules/FundingManager/FundingManager.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract FundingManagerMock is IFundingManager, Module {
    using SafeERC20 for IERC20;

    IERC20 private _token;

    function init(IProposal proposal_, Metadata memory metadata, bytes memory)
        public
        override(Module)
        initializer
    {
        __Module_init(proposal_, metadata);
    }

    function setToken(IERC20 newToken) public {
        _token = newToken;
    }

    function token() public view returns (IERC20) {
        return _token;
    }

    function deposit(uint amount) external {
        _token.safeTransferFrom(_msgSender(), address(this), amount);
    }

    function depositFor(address, uint amount) external {
        _token.safeTransferFrom(_msgSender(), address(this), amount);
    }

    function withdraw(uint amount) external {
        _token.safeTransfer(_msgSender(), amount);
    }

    function withdrawTo(address to, uint amount) external {
        _token.safeTransfer(to, amount);
    }

    function transferProposalToken(address to, uint amount) external {
        _token.safeTransfer(to, amount);
    }
}
