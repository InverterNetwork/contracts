// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// SuT
import {Module} from "src/modules/base/Module.sol";

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

contract ModuleInvariants is Module {
    // Mocks
    ProposalMock proposalMock;
    AuthorizerMock authorizerMock;

    uint counter;

    constructor() {
        authorizerMock = new AuthorizerMock();
        authorizerMock.setAllAuthorized(true);

        proposalMock = new ProposalMock(authorizerMock);

        // Has to be in own function to apply `initializer` modifier.
        _initModule();

        // Initialize proposal to enable module.
        address[] memory modules = new address[](1);
        modules[0] = address(this);
        proposalMock.init(modules);
    }

    function _initModule() internal initializer {
        __Module_init(proposalMock);
    }

    function echidna_proposal_variable_not_mutated_after_initialization()
        public
        returns (bool)
    {
        return address(__Module_proposal) == address(proposalMock);
    }
}
