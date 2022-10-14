// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Interfaces
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Mocks
import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

contract ModuleTest is Test {
    // Mocks
    AuthorizerMock internal _authorizer = new AuthorizerMock();
    ProposalMock internal _proposal = new ProposalMock(_authorizer);

    // Constants
    uint internal constant _MAJOR_VERSION = 1;
    string internal constant _GIT_URL = "https://github.com/org/module";

    IModule.Metadata internal _METADATA =
        IModule.Metadata(_MAJOR_VERSION, _GIT_URL);

    //--------------------------------------------------------------------------------
    // Setup

    function _setUpProposal(IModule module) internal virtual {
        address[] memory modules = new address[](1);
        modules[0] = address(module);

        _proposal.init(modules);
    }

    //--------------------------------------------------------------------------------
    // Error Helper Functions
    //
    // Prefixed with `_expect`.

    function _expectProposalCallbackFailure(string memory funcSig) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module_ProposalCallbackFailed(string)", funcSig
            )
        );
    }

    //--------------------------------------------------------------------------------
    // Assertion Helper Functions
    //
    // Prefixed with `_assert`.

    //--------------------------------------------------------------------------------
    // Fuzzer Helper Functions
    //
    // Prefixed with `_assume`.

    function _assumeNonEmptyString(string memory a) internal {
        vm.assume(bytes(a).length != 0);
    }

    function _assumeTimestampNotInPast(uint a) internal {
        vm.assume(a >= block.timestamp);
    }
}
