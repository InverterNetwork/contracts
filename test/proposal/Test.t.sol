// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {Proposal} from "src/proposal/Proposal.sol";

// Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

/**
 * Errors library for Proposal's custom errors.
 * Enables checking for errors with vm.expectRevert(Errors.<Error>).
 */
library Errors {
    //
    // OpenZeppelin Errors
    //
    bytes internal constant OZ__Initializable__AlreadyInitialized =
        bytes("Initializable: contract is already initialized");

    //
    // ModuleManager Errors
    //
    bytes internal constant Proposal__ModuleManager__OnlyCallableByModule = abi
        .encodeWithSignature("Proposal__ModuleManager__OnlyCallableByModule()");

    bytes internal constant Proposal__ModuleManager__AlreadyInitialized =
        abi.encodeWithSignature("Proposal__ModuleManager__AlreadyInitialized()");

    bytes internal constant Proposal__ModuleManager__ExecuteTxFromModuleFailed =
    abi.encodeWithSignature(
        "Proposal__ModuleManager__ExecuteTxFromModuleFailed()"
    );

    bytes internal constant Proposal__ModuleManager__InvalidModuleAddress = abi
        .encodeWithSignature("Proposal__ModuleManager__InvalidModuleAddress()");

    function Proposal__ModuleManager__ModuleAlreadyEnabled(address module)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "Proposal__ModuleManager__ModuleAlreadyEnabled(address)", module
        );
    }

    //
    // Proposal Errors
    //
    bytes internal constant Proposal__CallerNotAuthorized =
        abi.encodeWithSignature("Proposal__CallerNotAuthorized()");

    bytes internal constant Proposal__InvalidAuthorizer =
        abi.encodeWithSignature("Proposal__InvalidAuthorizer()");

    bytes internal constant Proposal__ExecuteTxFailed =
        abi.encodeWithSignature("Proposal__ExecuteTxFailed()");
}

/**
 * @dev Root contract for Proposal Test Contracts.
 *
 *      Provides setUp functions, access to common test utils and internal
 *      variables used throughout testing.
 */
abstract contract ProposalBaseTest is Test {
    Proposal proposal;

    // Mocks
    AuthorizerMock authorizer;

    // Helper structures.
    mapping(address => bool) modulesCache;

    // Constants copied from ModuleManager.
    address internal constant SENTINEL_MODULE = address(1);

    function setUp() public {
        authorizer = new AuthorizerMock();

        proposal = new Proposal();
    }

    modifier assumeValidProposalId(uint proposalId) {
        _;
    }

    modifier assumeValidFunders(address[] memory funders) {
        _;
    }

    modifier assumeValidModules(address[] memory modules_) {
        vm.assume(modules_.length != 0);

        address module;
        for (uint i; i < modules_.length; i++) {
            module = modules_[i];

            // Assume valid module address.
            vm.assume(module != address(0));
            vm.assume(module != SENTINEL_MODULE);

            // Assume module not authorizer instance.
            vm.assume(module != address(authorizer));

            // Assume unique module.
            vm.assume(!modulesCache[module]);

            // Add module to modules cache.
            modulesCache[module] = true;
        }

        _;
    }
}
