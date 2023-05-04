// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// SuT
import {LinkedIdList} from "src/common/LinkedIdList.sol";

contract LinkedIdListTest is Test {
    using LinkedIdList for LinkedIdList.List;

    LinkedIdList.List list;

    uint internal constant _SENTINEL = type(uint).max;

    function setUp() public {
        list.init();
    }

    function testDeploymentInvariants() public {
        assertEq(list.length(), 0);

        assertEq(list.lastId(), _SENTINEL);
        assertEq(list.listIds().length, 0);
    }

    //--------------------------------------------------------------------------------
    // Mutating Functions

    function testAddId(uint[] calldata seed) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory Ids = createIds(seed);

        uint previousId = _SENTINEL;

        uint length = Ids.length;
        for (uint i; i < length; i++) {
            uint id = Ids[i];
            id = bound(id, 1, _SENTINEL - 1);

            list.addId(id);

            assertEq(list.list[id], _SENTINEL);
            assertEq(list.list[previousId], id);
            assertEq(list.size, i + 1);
            previousId = id;
        }
    }

    //--------------------------------------------------------------------------------
    // Helper Functions

    //Create Ids that are not the same but still randomised
    function createIds(uint[] calldata seed)
        internal
        view
        returns (uint[] memory)
    {
        uint length = seed.length;

        uint[] memory Ids = new uint[](length);

        uint value;
        for (uint i; i < length; i++) {
            value += bound(seed[i], 1, 100);
            Ids[i] = value;
        }
        return Ids;
    }
}
