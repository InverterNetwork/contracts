// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IPayer} from "src/interfaces/IPayer.sol";

// Mocks
import {ModuleManagerMock} from "./base/ModuleManagerMock.sol";

contract ProposalMock is IProposal, ModuleManagerMock {
    IAuthorizer public authorizer;
    IPayer public payer;

    uint public proposalId;
    address[] public funders;
    address[] public modules;

    function init(
        IAuthorizer authorizer_,
        IPayer payer_
    ) external initializer {
        authorizer = authorizer_;
        payer = payer_;
    }

    function init(
        IAuthorizer authorizer_,
        IPayer payer_,
        address[] calldata modules_
    ) external initializer {
        authorizer = authorizer_;
        payer = payer_;

        __ModuleManager_init(modules_);
    }

    function init(
        uint proposalId_,
        address[] calldata funders_,
        address[] calldata modules_,
        IAuthorizer authorizer_,
        IPayer payer_
    ) external initializer {
        proposalId = proposalId_;
        funders = funders_;
        modules = modules_;
        authorizer = authorizer_;
        payer = payer_;

        __ModuleManager_init(modules_);
    }

    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory)
    {}

    function version() external pure returns (string memory) {
        return "1";
    }
}
