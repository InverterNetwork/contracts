// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Mock Dependencies
import {ModuleManagerMock} from "./base/ModuleManagerMock.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IPayer} from "src/interfaces/IPayer.sol";

import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

contract ProposalMock is IProposal, ModuleManagerMock {
    IAuthorizer public authorizer;
    IERC20 public paymentToken;
    IPayer public payer;

    uint public proposalId;
    address[] public funders;
    address[] public modules;

    constructor(IAuthorizer authorizer_) {
        authorizer = authorizer_;
    }

    function init(
        uint proposalId_,
        address[] calldata funders_,
        address[] calldata modules_,
        IAuthorizer authorizer_,
        IPayer payer_
    ) external {
        proposalId = proposalId_;
        funders = funders_;
        modules = modules_;
        authorizer = authorizer_;
        payer = payer_;
    }

    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory)
    {}

    function version() external pure returns (string memory) {
        return "1";
    }

    function initModules(address[] calldata modules_) public initializer {
        __ModuleManager_init(modules_);
    }
}
