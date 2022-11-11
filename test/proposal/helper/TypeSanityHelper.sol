// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

contract TypeSanityHelper is Test {
    address private _self;

    constructor(address self) {
        _self = self;
    }

    //--------------------------------------------------------------------------------
    // Helpers

    function assumeElemNotInSet(address[] memory set, address elem) public {
        for (uint i; i < set.length; i++) {
            vm.assume(elem != set[i]);
        }
    }

    //--------------------------------------------------------------------------------
    // Types for Proposal
    // Contract: Proposal.sol

    function assumeValidProposalId(uint id) public {
        vm.assume(id != 0);
    }

    //--------------------------------------------------------------------------------
    // Types for Module
    // Contract: base/ModuleManager.sol

    address private constant _SENTINEL_MODULE = address(0x1);

    mapping(address => bool) moduleCache;

    function assumeValidModules(address[] memory modules) public {
        for (uint i; i < modules.length; i++) {
            assumeValidModule(modules[i]);

            // Assume module unique.
            vm.assume(!moduleCache[modules[i]]);

            // Add module to cache.
            moduleCache[modules[i]] = true;
        }
    }

    function assumeValidModule(address module) public {
        address[] memory invalids = createInvalidModules();

        for (uint i; i < invalids.length; i++) {
            vm.assume(module != invalids[i]);
        }
    }

    function createInvalidModules() public view returns (address[] memory) {
        address[] memory invalids = new address[](3);

        invalids[0] = address(0);
        invalids[1] = _SENTINEL_MODULE;
        invalids[2] = _self;

        return invalids;
    }

    //--------------------------------------------------------------------------------
    // Types for Funder
    // Contract: base/FunderManager.sol

    function assumeValidFunders(address[] memory funders) public {}

    // @todo nejc, mp: FunderManager Type Sanity check- and creater functions.

    //--------------------------------------------------------------------------------
    // Types for Contributor
    // Contract: base/ContributorManager.sol

    address private constant _SENTINEL_CONTRIBUTOR = address(0x1);

    mapping(address => bool) contributorCache;

    function assumeValidContributors(address[] memory addrs) public {
        for (uint i; i < addrs.length; i++) {
            assumeValidContributor(addrs[i]);

            // Assume contributor address unique.
            vm.assume(!contributorCache[addrs[i]]);

            // Add contributor address to cache.
            contributorCache[addrs[i]] = true;
        }
    }

    function assumeValidContributor(address a) public {
        address[] memory invalids = createInvalidContributors();

        for (uint i; i < invalids.length; i++) {
            vm.assume(a != invalids[i]);
        }
    }

    function createInvalidContributors()
        public
        view
        returns (address[] memory)
    {
        address[] memory invalids = new address[](3);

        invalids[0] = address(0);
        invalids[1] = _SENTINEL_CONTRIBUTOR;
        invalids[2] = _self;

        return invalids;
    }

    function createInvalidContributorNames()
        public
        pure
        returns (string[] memory)
    {
        string[] memory invalids = new string[](1);

        invalids[0] = "";

        return invalids;
    }

    function createInvalidContributorRoles()
        public
        pure
        returns (string[] memory)
    {
        string[] memory invalids = new string[](1);

        invalids[0] = "";

        return invalids;
    }

    function createInvalidContributorSalaries()
        public
        pure
        returns (uint[] memory)
    {
        uint[] memory invalids = new uint[](1);

        invalids[0] = 0;

        return invalids;
    }
}
