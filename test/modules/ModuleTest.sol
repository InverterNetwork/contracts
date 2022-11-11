// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

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
    Proposal internal _proposal = new Proposal();

    // Mocks
    AuthorizerMock internal _authorizer = new AuthorizerMock();
    ERC20Mock internal _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();

    // Proposal Constants
    uint internal constant _PROPOSAL_ID = 1;

    // Module Constants
    uint internal constant _MAJOR_VERSION = 1;
    string internal constant _GIT_URL = "https://github.com/org/module";

    IModule.Metadata internal _METADATA =
        IModule.Metadata(_MAJOR_VERSION, _GIT_URL);

    //--------------------------------------------------------------------------------
    // Setup

    function _setUpProposal(IModule module) internal virtual {
        address[] memory modules = new address[](1);
        modules[0] = address(module);

        // @audit-issue Inheritance error.
        _proposal.init(
            _PROPOSAL_ID, _token, modules, _authorizer, _paymentProcessor
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

    function _assumeNonEmptyString(string memory a) internal {
        vm.assume(bytes(a).length != 0);
    }

    function _assumeTimestampNotInPast(uint a) internal {
        vm.assume(a >= block.timestamp);
    }
}
