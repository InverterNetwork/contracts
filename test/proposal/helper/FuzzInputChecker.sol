// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

/**
 * @dev Helper contract providing `_assume...` functions to check fuzzer inputs.
 */
abstract contract FuzzInputChecker is Test {
    // Helper Caches.
    mapping(address => bool) modulesCache;

    // Constants copied from ModuleManager.
    address internal constant SENTINEL_MODULE = address(1);

    function _assumeValidProposalId(uint proposalId) internal {}

    function _assumeValidFunders(address[] memory funders) internal {}

    function _assumeValidModulesWithAuthorizer(
        address[] memory modules,
        IAuthorizer authorizer
    ) internal {
        _assumeValidModules(modules);

        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            // Assume module not authorizer instance.
            vm.assume(module != address(authorizer));
        }
    }

    function _assumeValidModules(address[] memory modules) internal {
        vm.assume(modules.length != 0);

        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            // Assume valid module address.
            vm.assume(module != address(0));

            // Assume unique module.
            vm.assume(!modulesCache[module]);

            // Add module to modules cache.
            modulesCache[module] = true;
        }
    }
}
