// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Mock Dependencies
import {ModuleManagerMock} from "./base/ModuleManagerMock.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

contract ProposalMock is IProposal, ModuleManagerMock {
    IAuthorizer public authorizer;

    constructor(IAuthorizer authorizer_) {
        authorizer = authorizer_;
    }

    /// @dev Currently unused. Implemented due to inheritance.
    function init(
        uint proposalId,
        address[] calldata funders,
        address[] calldata modules,
        IAuthorizer authorizer_
    ) external {

    }

    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory)
    {}

    function version() external pure returns (string memory) {
        return "1";
    }
}
