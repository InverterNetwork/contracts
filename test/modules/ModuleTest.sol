// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {OrchestratorV1Mock} from
    "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";
import {FeeManager_v1} from "src/external/fees/FeeManager_v1.sol";
import {GovernorV1Mock} from "test/utils/mocks/external/GovernorV1Mock.sol";
import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";
import {ModuleFactoryV1Mock} from
    "test/utils/mocks/factories/ModuleFactoryV1Mock.sol";

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";

// Mocks
import {OrchestratorV1Mock} from
    "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";
import {FundingManagerV1Mock} from
    "test/utils/mocks/modules/FundingManagerV1Mock.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {PaymentProcessorV1Mock} from
    "test/utils/mocks/modules/PaymentProcessorV1Mock.sol";
// External Dependencies
import {TransparentUpgradeableProxy} from
    "@oz/proxy/transparent/TransparentUpgradeableProxy.sol";
/**
 * @dev Base class for module implementation test contracts.
 */

abstract contract ModuleTest is Test {
    OrchestratorV1Mock _orchestrator;

    // Mocks
    FundingManagerV1Mock _fundingManager;
    AuthorizerV1Mock _authorizer;
    ERC20Mock _token = new ERC20Mock("Mock Token", "MOCK");
    PaymentProcessorV1Mock _paymentProcessor = new PaymentProcessorV1Mock();

    GovernorV1Mock governor = new GovernorV1Mock();
    ModuleFactoryV1Mock moduleFactory = new ModuleFactoryV1Mock();

    FeeManager_v1 feeManager;
    address treasury = makeAddr("treasury");

    // Deploy a forwarder used to enable metatransactions
    TransactionForwarder_v1 _forwarder =
        new TransactionForwarder_v1("TransactionForwarder_v1");

    // Orchestrator_v1 Constants
    uint constant _ORCHESTRATOR_ID = 1;

    // Module_v1 Constants
    uint constant _MAJOR_VERSION = 1;
    uint constant _MINOR_VERSION = 0;
    string constant _URL = "https://github.com/organization/module";
    string constant _TITLE = "Module_v1";

    IModule_v1.Metadata _METADATA =
        IModule_v1.Metadata(_MAJOR_VERSION, _MINOR_VERSION, _URL, _TITLE);

    //--------------------------------------------------------------------------
    // Setup
    function _setUpOrchestrator(IModule_v1 module) internal virtual {
        //Needs to be a proxy for the notInitialized Check
        feeManager = FeeManager_v1(
            address(
                new TransparentUpgradeableProxy( // based on openzeppelins TransparentUpgradeableProxy
                    address(new FeeManager_v1()), // Implementation Address
                    address(this), // Admin
                    bytes("") // data field that could have been used for calls, but not necessary
                )
            )
        );
        feeManager.init(address(this), treasury, 0, 0);
        governor.setFeeManager(address(feeManager));

        address[] memory modules = new address[](1);
        modules[0] = address(module);

        address impl = address(new OrchestratorV1Mock(address(_forwarder)));
        _orchestrator = OrchestratorV1Mock(Clones.clone(impl));

        impl = address(new FundingManagerV1Mock());
        _fundingManager = FundingManagerV1Mock(Clones.clone(impl));

        impl = address(new AuthorizerV1Mock());
        _authorizer = AuthorizerV1Mock(Clones.clone(impl));

        _orchestrator.init(
            _ORCHESTRATOR_ID,
            address(moduleFactory),
            modules,
            _fundingManager,
            _authorizer,
            _paymentProcessor,
            governor
        );

        _authorizer.init(_orchestrator, _METADATA, abi.encode(address(this)));

        _fundingManager.init(_orchestrator, _METADATA, abi.encode(""));
        _fundingManager.setToken(IERC20(address(_token)));
    }

    //--------------------------------------------------------------------------
    // Test: Initialization
    //
    // MUST be implemented in downstream contract.

    function testInit() public virtual;

    function testReinitFails() public virtual;

    //--------------------------------------------------------------------------
    // Assertion Helper Functions
    //
    // Prefixed with `_assert`.

    //--------------------------------------------------------------------------
    // Fuzzer Helper Functions
    //
    // Prefixed with `_assume`.

    //--------------------------------------------------------------------------
    // Helpers

    /// This function is intended to help in the case the number is intended to be converted into a token with a different decimal value.
    /// @param number The number to be bounded
    /// @param tokenDecimals The number of decimals the token which will be converted has
    /// @param min The minimum value the number can be
    /// @param max The maximum value the number can be, including the referenceDecimals
    /// @param referenceDecimals The number of decimals the reference token has, which the token will be converted into
    /// @return amount The bounded number
    function _bound_for_decimal_conversion(
        uint number,
        uint min,
        uint max,
        uint tokenDecimals,
        uint referenceDecimals
    ) internal view returns (uint amount) {
        assert(tokenDecimals <= referenceDecimals);

        uint decimalDiff = referenceDecimals - tokenDecimals;
        uint newMax = max / 10 ** decimalDiff;

        amount = bound(number, min, newMax);
    }

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

            // Assume address unique.
            vm.assume(!addressCache[addresses[i]]);

            // Add address to cache.
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
