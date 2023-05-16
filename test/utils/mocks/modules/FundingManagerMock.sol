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

contract FundingManagerMock is IFundingManager, Module {
    IERC20 internal _token;

    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) public override(Module) initializer {
        __Module_init(proposal_, metadata);

        // Read first authorized address from configdata.
        IERC20 token_ = abi.decode(configdata, (IERC20));

        _token = token_;
    }

    function token() public view returns (IERC20) {
        return _token;
    }

    function deposit(uint amount) external {}
    function depositFor(address to, uint amount) external {}

    function withdraw(uint amount) external {}
    function withdrawTo(address to, uint amount) external {}

    function transferProposalToken(address to, uint amount) external {}
}
