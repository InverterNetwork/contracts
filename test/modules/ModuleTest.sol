// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Orchestrator} from "src/orchestrator/Orchestrator.sol";

// Internal Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";

// Mocks
import {FundingManagerMock} from
    "test/utils/mocks/modules/FundingManagerMock.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {PaymentProcessorMock} from
    "test/utils/mocks/modules/PaymentProcessorMock.sol";

/**
 * @dev Base class for module implementation test contracts.
 */
abstract contract ModuleTest is Test {
    Orchestrator _orchestrator;

    // Mocks
    FundingManagerMock _fundingManager = new FundingManagerMock();
    AuthorizerMock _authorizer = new AuthorizerMock();
    ERC20Mock _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorMock _paymentProcessor = new PaymentProcessorMock();

    // Orchestrator Constants
    uint constant _ORCHESTRATOR_ID = 1;

    // Module Constants
    uint constant _MAJOR_VERSION = 1;
    uint constant _MINOR_VERSION = 1;
    string constant _URL = "https://github.com/organization/module";
    string constant _TITLE = "Module";

    IModule.Metadata _METADATA =
        IModule.Metadata(_MAJOR_VERSION, _MINOR_VERSION, _URL, _TITLE);

    //--------------------------------------------------------------------------------
    // Setup

    function _setUpOrchestrator(IModule module) internal virtual {
        address[] memory modules = new address[](1);
        modules[0] = address(module);

        address impl = address(new Orchestrator());
        _orchestrator = Orchestrator(Clones.clone(impl));

        _orchestrator.init(
            _ORCHESTRATOR_ID,
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor
        );
        _fundingManager.setToken(IERC20(address(_token)));
    }

    //--------------------------------------------------------------------------------
    // Test: Initialization
    //
    // MUST be implemented in downstream contract.

    function testInit() public virtual {}

    function testReinitFails() public virtual {}

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

    function _assumeNonEmptyString(string memory a) internal pure {
        vm.assume(bytes(a).length != 0);
    }

    function _assumeTimestampNotInPast(uint a) internal view {
        vm.assume(a >= block.timestamp);
    }

    // assumeElemNotInSet functions for different types:

    function _assumeElemNotInSet(address[] memory set, address elem)
        internal
        pure
    {
        for (uint i; i < set.length; ++i) {
            vm.assume(elem != set[i]);
        }
    }

    function _assumeElemNotInSet(uint[] memory set, uint elem) internal pure {
        for (uint i; i < set.length; ++i) {
            vm.assume(elem != set[i]);
        }
    }

    function _assumeElemNotInSet(string[] memory set, string memory elem)
        internal
        pure
    {
        for (uint i; i < set.length; ++i) {
            vm.assume(keccak256(bytes(elem)) != keccak256(bytes(set[i])));
        }
    }

    function _assumeElemNotInSet(bytes[] memory set, bytes memory elem)
        internal
        pure
    {
        for (uint i; i < set.length; ++i) {
            vm.assume(
                keccak256(abi.encodePacked(elem))
                    != keccak256(abi.encodePacked(set[i]))
            );
        }
    }

    // Address Sanity Checkers
    mapping(address => bool) addressCache;

    function _assumeValidAddresses(address[] memory addresses) internal {
        for (uint i; i < addresses.length; ++i) {
            _assumeValidAddress(addresses[i]);

            // Assume module unique.
            vm.assume(!addressCache[addresses[i]]);

            // Add module to cache.
            addressCache[addresses[i]] = true;
        }
    }

    function _assumeValidAddress(address user) internal view {
        address[] memory invalids = _createInvalidAddresses();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(user != invalids[i]);
        }
    }

    function _createInvalidAddresses()
        internal
        view
        returns (address[] memory)
    {
        address[] memory modules = _orchestrator.listModules();

        address[] memory invalids = new address[](modules.length + 4);

        for (uint i; i < modules.length; ++i) {
            invalids[i] = modules[i];
        }

        invalids[invalids.length - 4] = address(0);
        invalids[invalids.length - 3] = address(this);
        invalids[invalids.length - 2] = address(_orchestrator);
        invalids[invalids.length - 1] = address(_token);

        return invalids;
    }
}
