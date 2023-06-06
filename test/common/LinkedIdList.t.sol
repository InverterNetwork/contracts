// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

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
    // Modifier

    function testValidNewId(uint[] calldata seed, uint id) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        addIds(ids);

        if (containsId(ids, id) || id == 0) {
            vm.expectRevert(
                LinkedIdList.Library__LinkedIdList__InvalidNewId.selector
            );
        }
        list.addId(id);
    }

    function testValidId(uint[] calldata seed, uint id) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        addIds(ids);

        uint prevId;

        if (!containsId(ids, id) || id == _SENTINEL) {
            vm.expectRevert(
                LinkedIdList.Library__LinkedIdList__InvalidId.selector
            );
        } else {
            prevId = list.getPreviousId(id);
        }
        list.removeId(prevId, id);
    }

    function testValidPosition(uint[] calldata seed, uint id) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        addIds(ids);

        if (!containsId(ids, id) && id != _SENTINEL) {
            vm.expectRevert(
                LinkedIdList.Library__LinkedIdList__InvalidPosition.selector
            );
        }
        list.getPreviousId(id);
    }

    function testOnlyConsecutiveIds(uint[] calldata seed, uint prevId) public {
        vm.assume(seed.length < 1000); //Reasonable size
        vm.assume(seed.length > 0);

        uint randomId;

        uint[] memory ids = createIds(seed);

        addIds(ids);

        //RandomId has to be part of the list and is not _SENTINEL
        randomId = ids[bound(seed[0], 0, seed.length - 1)];

        if (list.getPreviousId(randomId) != prevId) {
            vm.expectRevert(
                LinkedIdList.Library__LinkedIdList__IdNotConsecutive.selector
            );
        }
        list.removeId(prevId, randomId);
    }

    function testValidMoveParameter(
        uint[] calldata seed,
        uint id,
        uint prevId,
        uint idToPositionAfter
    ) public {
        vm.assume(seed.length < 1000); //Reasonable size
        vm.assume(seed.length > 0);
        vm.assume(prevId < 2000);
        vm.assume(id < 2000);
        vm.assume(idToPositionAfter < 2000);

        uint[] memory ids = createIds(seed);
        addIds(ids);

        if (!containsId(ids, id) || id == _SENTINEL) {
            vm.expectRevert(
                LinkedIdList.Library__LinkedIdList__InvalidId.selector
            );
        } else if (
            !containsId(ids, idToPositionAfter)
                && idToPositionAfter != _SENTINEL
        ) {
            vm.expectRevert(
                LinkedIdList.Library__LinkedIdList__InvalidPosition.selector
            );
        }
        //Check if it is a valid intermediate position
        else if (
            (id == idToPositionAfter) //Make sure it doesnt move after itself
                || (idToPositionAfter == prevId) //Make sure it doesnt move before itself
        ) {
            vm.expectRevert(
                LinkedIdList
                    .Library__LinkedIdList__InvalidIntermediatePosition
                    .selector
            );
        } else if (list.getPreviousId(id) != prevId) {
            vm.expectRevert(
                LinkedIdList.Library__LinkedIdList__IdNotConsecutive.selector
            );
        }

        list.moveIdInList(id, prevId, idToPositionAfter);
    }

    //--------------------------------------------------------------------------------
    // View Functions

    function testListIds(uint[] calldata seed) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        uint length = ids.length;
        addIds(ids);

        uint[] memory compareList = list.listIds();

        assertEq(compareList.length, length);

        for (uint i; i < length; i++) {
            assertEq(compareList[i], ids[i]);
        }
    }

    function testIsExistingId(uint[] calldata seed, uint randomId) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        addIds(ids);

        bool expectedValue; //False

        if (containsId(list.listIds(), randomId)) {
            expectedValue = true;
        }
        assertEq(list.isExistingId(randomId), expectedValue);
    }

    function testGetPreviousId(uint[] calldata seed) public {
        vm.assume(seed.length < 1000); //Reasonable size

        uint[] memory ids = createIds(seed);
        uint length = ids.length;
        addIds(ids);

        uint prevId;
        for (uint i; i < length; i++) {
            if (i == 0) prevId = _SENTINEL;
            else prevId = ids[i - 1];
            assertEq(list.getPreviousId(ids[i]), prevId);
        }
    }

    function testGetPreviousIdModifier() public {
        //Check validPosition is in place
        vm.expectRevert(
            LinkedIdList.Library__LinkedIdList__InvalidPosition.selector
        );

        list.getPreviousId(0);
    }

    function testGetNextIdModifier() public {
        //Check validPosition is in place
        vm.expectRevert(
            LinkedIdList.Library__LinkedIdList__InvalidPosition.selector
        );

        list.getNextId(0);
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

    function testAddIdModifier() public {
        list.addId(1);

        //Check validNewId is in place
        vm.expectRevert(
            LinkedIdList.Library__LinkedIdList__InvalidNewId.selector
        );

        list.addId(1);
    }

    function testRemoveId(uint[] calldata seed) public {
        vm.assume(seed.length > 0); //Reasonable size
        vm.assume(seed.length < 1000);

        //Check for validId
        vm.expectRevert(LinkedIdList.Library__LinkedIdList__InvalidId.selector);

        list.removeId(_SENTINEL, 0);

        //Add Ids to the list
        uint[] memory ids = createIds(seed);

        uint id;

        uint length = ids.length;
        addIds(ids);

        //Check for validId
        vm.expectRevert(
            LinkedIdList.Library__LinkedIdList__IdNotConsecutive.selector
        );

        //Should not be consecutive
        list.removeId(ids[0], ids[2]);

        //Check if removel works correct
        uint nextId;
        uint prevId;

        //Reverse loop to check for correct updating of list.last
        for (uint i = length; i > 0; i--) {
            id = ids[i];
            nextId = list.getNextId(id);
            if (i == 0) {
                prevId = _SENTINEL;
                id = ids[i];
            } else {
                prevId = ids[i - 1];
            }

            list.removeId(prevId, id);
            assertFalse(list.isExistingId(id));
            assertEq(list.getNextId(prevId), nextId);
            assertEq(list.length(), i);
            assertEq(list.lastId(), prevId);
        }

        //Check List is empty
        assertEq(list.length(), 0);
        assertEq(list.lastId(), _SENTINEL);
        assertEq(list.listIds().length, 0);
    }

    function testRemoveIdModifier() public {
        list.addId(1);

        //Check validId is in place
        vm.expectRevert(LinkedIdList.Library__LinkedIdList__InvalidId.selector);

        list.removeId(1, 2);

        //Check onlyConsecutiveIds is in place
        vm.expectRevert(
            LinkedIdList.Library__LinkedIdList__IdNotConsecutive.selector
        );

        list.removeId(1, 0);
    }

    function testMoveId(uint[] calldata seed, uint idToMoveToIndex) public {
        vm.assume(seed.length > 2); //Reasonable size
        vm.assume(seed.length < 20);

        idToMoveToIndex = bound(idToMoveToIndex, 0, seed.length); //This might break out of Index Range because idToMoveTo can be _SENTINTEL

        uint[] memory ids = createIds(seed);

        addIds(ids);

        uint randomId = ids[bound(seed[0], 0, seed.length - 1)]; //Use Seed to create a randomId, this is to prevent StackTooDeep
        uint prevId = list.getPreviousId(randomId);
        uint idToMoveTo;
        //If Index equals 20 use it as _SENTINEL
        if (idToMoveToIndex == seed.length) {
            idToMoveTo = _SENTINEL;
        } else {
            idToMoveTo = ids[idToMoveToIndex];
        }

        vm.assume(randomId != idToMoveTo);
        vm.assume(idToMoveTo != prevId);

        list.moveIdInList(randomId, prevId, idToMoveTo);
        assertTrue(list.getNextId(idToMoveTo) == randomId);
        assertTrue(list.getNextId(prevId) != randomId);

        //Check if _last is set correctly

        if (idToMoveToIndex == seed.length - 1) {
            assertTrue(list.getNextId(randomId) == _SENTINEL);
        }
    }

    function testMoveIdInListModifier() public {
        //Check validId is in place for id
        vm.expectRevert(LinkedIdList.Library__LinkedIdList__InvalidId.selector);

        list.moveIdInList(0, 0, 0);

        list.addId(0);
        list.addId(1);

        //Check validPosition is in place for idToPositionAfter
        vm.expectRevert(LinkedIdList.Library__LinkedIdList__InvalidId.selector);

        list.moveIdInList(0, 0, 2);

        //Check intermediatePosition is in place
        vm.expectRevert(LinkedIdList.Library__LinkedIdList__InvalidId.selector);

        list.moveIdInList(0, 1, 0);

        //Check intermediatePosition is in place
        vm.expectRevert(LinkedIdList.Library__LinkedIdList__InvalidId.selector);

        list.moveIdInList(0, 1, 1);

        //Check onlyConsecutiveIds is in place
        vm.expectRevert(
            LinkedIdList.Library__LinkedIdList__IdNotConsecutive.selector
        );

        list.moveIdInList(0, 0, 1);
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

    function addIds(uint[] memory ids) internal {
        uint length = ids.length;
        for (uint i; i < length; i++) {
            list.addId(ids[i]);
        }
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

    function idIndex(uint[] memory array, uint id)
        internal
        pure
        returns (uint)
    {
        uint length = array.length;
        for (uint i; i < length; i++) {
            if (array[i] == id) {
                return i;
            }
        }
        return type(uint).max;
    }
}
