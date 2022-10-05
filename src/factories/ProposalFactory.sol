// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";
import {Context} from "@oz/utils/Context.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

contract ProposalFactory {
    address public immutable target;
    address public immutable modulesFactory;

    uint private _proposalIdCounter;

    constructor(address target_, address modulesFactory_) {
        target = target_;
        modulesFactory = modulesFactory_;
    }

    function createProposal(
        address[] calldata funders,
        address[] calldata modules,
        IAuthorizer authorizer
    ) external returns (IProposal) {
        return _createProposal(funders, modules, authorizer);
    }

    function _createProposal(
        address[] calldata funders,
        address[] calldata modules,
        IAuthorizer authorizer
    ) internal returns (IProposal) {
        address clone = Clones.clone(target);
        IProposal(clone).init(
            _proposalIdCounter++, funders, modules, authorizer
        );

        return IProposal(clone);
    }
}
