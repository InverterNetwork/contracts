// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Internal Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Mocks
// @todo Authorizer should be moved to utils/mocks/modules/ ?
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

/**
 * @dev Base class for module implementation test contracts.
 */
abstract contract ModuleTest is Test {
    using LibString for string;

    Proposal _proposal;

    // Mocks
    AuthorizerMock _authorizer = new AuthorizerMock();
    ERC20Mock _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();

    // Proposal Constants
    uint constant _PROPOSAL_ID = 1;

    // Module Constants
    uint constant _MAJOR_VERSION = 1;
    uint constant _MINOR_VERSION = 1;
    string constant _URL = "https://github.com/organization/module";
    string constant _TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(_MAJOR_VERSION, _MINOR_VERSION, _URL, _TITLE);

    //--------------------------------------------------------------------------------
    // Setup

    function _setUpProposal(IModule module) internal virtual {
        address[] memory modules = new address[](1);
        modules[0] = address(module);

        address impl = address(new Proposal());
        _proposal = Proposal(Clones.clone(impl));

        _proposal.init(
            _PROPOSAL_ID,
            address(this),
            _token,
            modules,
            _authorizer,
            _paymentProcessor
        );
    }

    //--------------------------------------------------------------------------------
    // Test: Initialization
    //
    // MUST be implemented in downstream contract.

    function testInit() public virtual;

    function testReinitFails() public virtual;

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

    //--------------------------------------------------------------------------------
    // Helpers

    function _assumeNonEmptyString(string memory a) internal {
        vm.assume(!a.isEmpty());
    }

    function _assumeTimestampNotInPast(uint a) internal {
        vm.assume(a >= block.timestamp);
    }

    // assumeElemNotInSet functions for different types:

    function _assumeElemNotInSet(address[] memory set, address elem) internal {
        for (uint i; i < set.length; ++i) {
            vm.assume(elem != set[i]);
        }
    }

    function _assumeElemNotInSet(uint[] memory set, uint elem) internal {
        for (uint i; i < set.length; ++i) {
            vm.assume(elem != set[i]);
        }
    }

    function _assumeElemNotInSet(string[] memory set, string memory elem)
        internal
    {
        for (uint i; i < set.length; ++i) {
            vm.assume(!elem.equals(set[i]));
        }
    }
}
