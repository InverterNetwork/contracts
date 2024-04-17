// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Module, IModule, IOrchestrator_v1} from "src/modules/base/Module.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract FundingManagerMock is IFundingManager, Module {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module)
        returns (bool)
    {
        bytes4 interfaceId_IFundingManager = type(IFundingManager).interfaceId;
        return interfaceId == interfaceId_IFundingManager
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    IERC20 private _token;

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) public override(Module) initializer {
        __Module_init(orchestrator_, metadata);
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

    function transferOrchestratorToken(address to, uint amount) external {
        _token.safeTransfer(to, amount);
    }
}
