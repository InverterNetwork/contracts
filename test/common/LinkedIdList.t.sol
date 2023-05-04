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
    // View Functions

    function testListIds(uint[] calldata seed) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        uint length = ids.length;
        for (uint i; i < length; i++) {
            list.addId(ids[i]);
        }

        uint[] memory compareList = list.listIds();

        assertEq(compareList.length, length);

        for (uint i; i < length; i++) {
            assertEq(compareList[i], ids[i]);
        }
    }

    function testIsExistingId(uint[] calldata seed, uint randomId) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        uint length = ids.length;
        for (uint i; i < length; i++) {
            list.addId(ids[i]);
        }

        bool expectedValue; //False

        if (containsId(ids, randomId)) {
            expectedValue = true;
        }
        assertEq(list.isExistingId(randomId), expectedValue);
    }

    function testGetPreviousId(uint[] calldata seed) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        uint length = ids.length;
        for (uint i; i < length; i++) {
            list.addId(ids[i]);
        }

        uint prevId;
        for (uint i; i < length; i++) {
            if (i == 0) prevId = _SENTINEL;
            else prevId = ids[i - 1];
            assertEq(list.getPreviousId(ids[i]), prevId);
        }
    }

    //--------------------------------------------------------------------------------
    // Mutating Functions

    function testAddId(uint[] calldata seed) public {
        vm.assume(seed.length > 0); //Reasonable size
        vm.assume(seed.length < 1000);

        uint[] memory ids = createIds(seed);

        uint previousId = _SENTINEL;

        uint length = ids.length;
        for (uint i; i < length; i++) {
            uint id = ids[i];
            id = bound(id, 1, _SENTINEL - 1);

            list.addId(id);

            assertEq(list.list[id], _SENTINEL);
            assertEq(list.list[previousId], id);
            assertEq(list.size, i + 1);
            assertEq(list.last, id);
            previousId = id;
        }

        //Check for validNewId

        vm.expectRevert(
            LinkedIdList.Library__LinkedIdList__InvalidNewId.selector
        );

        list.addId(ids[0]);
    }

    //--------------------------------------------------------------------------------
    // Helper Functions

    //Create ids that are not the same but still randomised
    function createIds(uint[] calldata seed)
        internal
        view
        returns (uint[] memory)
    {
        uint length = seed.length;

        uint[] memory ids = new uint[](length);

        uint value;
        for (uint i; i < length; i++) {
            value += bound(seed[i], 1, 100);
            ids[i] = value;
        }
        return ids;
    }

    function containsId(uint[] memory array, uint id)
        internal
        pure
        returns (bool)
    {
        uint length = array.length;
        for (uint i; i < length; i++) {
            if (array[i] == id) {
                return true;
            }
        }
        return false;
    }
}
