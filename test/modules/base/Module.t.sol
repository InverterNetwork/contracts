// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

/**
 * Errors library for Module's custom errors.
 * Enables checking for errors with vm.expectRevert(Errors.<Error>).
 */
library Errors {
    bytes internal constant Module__CallerNotAuthorized =
        abi.encodeWithSignature("Module__CallerNotAuthorized()");

    bytes internal constant Module__OnlyCallableByProposal =
        abi.encodeWithSignature("Module__OnlyCallableByProposal()");

    bytes internal constant Module__InvalidProposalAddress =
        abi.encodeWithSignature("Module__InvalidProposalAddress()");

    bytes internal constant Module__WantProposalContext =
        abi.encodeWithSignature("Module__WantProposalContext()");
}

contract ModuleTest is Test {
    ModuleMock module;

    // Mocks
    ProposalMock proposal;
    AuthorizerMock authorizer;

    function setUp() public {
        authorizer = new AuthorizerMock();
        proposal = new ProposalMock(authorizer);

        module = new ModuleMock();
    }

    function testLol() public {}
}
