// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/*
Assumptions
-Continous Usage of List
-List is initiated with init ->once<-
-used ids are unique
*/

library LinkedIdList {
    struct List {
        /// @dev Size of the list
        uint size;
        /// @dev Marks the last element of the list.
        /// @dev Always links back to the _SENTINEL.
        uint last;
        /// @dev List of Ids
        mapping(uint => uint) list;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given id invalid.
    error Library__LinkedIdList__InvalidId();

    /// @notice Given new id invalid.
    error Library__LinkedIdList__InvalidNewId();

    /// @notice Given position in list is invalid.
    error Library__LinkedIdList__InvalidPosition();

    /// @notice Given ids are not consecutive.
    error Library__LinkedIdList__IdNotConsecutive();

    /// @notice Given ids are not consecutive.
    error Library__LinkedIdList__InvalidIntermediatePosition();

    //--------------------------------------------------------------------------
    // Modifier

    modifier validNewId(List storage self, uint id) {
        if (isExistingId(self, id) || id == 0) {
            revert Library__LinkedIdList__InvalidNewId();
        }
        _;
    }

    modifier validId(List storage self, uint id) {
        if (!isExistingId(self, id)) {
            revert Library__LinkedIdList__InvalidId();
        }
        _;
    }

    modifier validPosition(List storage self, uint id) {
        if (self.list[id] == 0) {
            revert Library__LinkedIdList__InvalidPosition();
        }
        _;
    }

    modifier onlyConsecutiveIds(List storage self, uint prevId, uint id) {
        if (self.list[prevId] != id) {
            revert Library__LinkedIdList__IdNotConsecutive();
        }
        _;
    }

    /// @dev prevId is checked by consecutiveId to be valid
    modifier validMoveParameter(
        List storage self,
        uint id,
        uint prevId,
        uint idToPositionAfter
    ) {
        //Check that id is existing
        if (!isExistingId(self, id)) {
            revert Library__LinkedIdList__InvalidId();
        }
        //Check that idToPositionAfter is in the list
        if (self.list[idToPositionAfter] == 0) {
            revert Library__LinkedIdList__InvalidPosition();
        }
        //Check if it is a valid intermediate position
        if (
            (id == idToPositionAfter) //Make sure it doesnt move after itself
                || (idToPositionAfter == prevId) //Make sure it doesnt move before itself
        ) {
            revert Library__LinkedIdList__InvalidIntermediatePosition();
        }

        //Check for Consecutive Id
        if (self.list[prevId] != id) {
            revert Library__LinkedIdList__IdNotConsecutive();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the beginning of the list.
    /// @dev Unrealistic to have that many ids.
    uint internal constant _SENTINEL = type(uint).max;

    //--------------------------------------------------------------------------
    // Init Function

    /// @dev should never be called more than once
    function init(List storage self) internal {
        //set Sentinel to link back to itself to initiate List
        self.list[_SENTINEL] = _SENTINEL;
        self.last = _SENTINEL;
    }

    //--------------------------------------------------------------------------
    // View Functions

    function length(List storage self) internal view returns (uint) {
        return self.size;
    }

    /// @dev Returns the last id in
    function lastId(List storage self) internal view returns (uint) {
        return self.last;
    }

    /// @notice lists the ids contained in the linked list
    /// @dev Returns an array
    /// @param self : the linked List from where the ids should be listed
    /// @return array of ids that are contained in the list
    function listIds(List storage self) internal view returns (uint[] memory) {
        uint[] memory result = new uint256[](self.size);

        // Populate result array.
        uint index;
        uint elem = self.list[_SENTINEL];
        while (elem != _SENTINEL) {
            result[index] = elem;
            elem = self.list[elem];
            index++;
        }

        return result;
    }

    function isExistingId(List storage self, uint id)
        internal
        view
        returns (bool)
    {
        //Return true if id is in list and not Sentinel
        return self.list[id] != 0 && id != _SENTINEL;
    }

    ///@dev id and prevId can be _SENTINEL
    function getPreviousId(List storage self, uint id)
        internal
        view
        validPosition(self, id)
        returns (uint prevId)
    {
        if (id == _SENTINEL) {
            return self.last;
        }
        uint[] memory Ids = listIds(self);

        uint len = Ids.length;
        for (uint i; i < len; ++i) {
            if (Ids[i] == id) {
                return i != 0 ? Ids[i - 1] : _SENTINEL;
            }
        }
    }

    ///@dev id and nextId can be _SENTINEL
    function getNextId(List storage self, uint id)
        internal
        view
        validPosition(self, id)
        returns (uint nextId)
    {
        return self.list[id];
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    // add To list at last position
    function addId(List storage self, uint id) internal validNewId(self, id) {
        self.list[self.last] = id;
        self.list[id] = _SENTINEL;
        self.last = id;
        self.size++;
    }

    function removeId(List storage self, uint prevId, uint id)
        internal
        validId(self, id)
        onlyConsecutiveIds(self, prevId, id)
    {
        // Remove id from list and decrease size.
        self.list[prevId] = self.list[id];
        delete self.list[id];
        self.size--;

        // In case last element was removed, update _last to its previous
        // element.
        if (id == self.last) {
            self.last = prevId;
        }
    }

    function moveIdInList(
        List storage self,
        uint id,
        uint prevId,
        uint idToPositionAfter
    ) internal validMoveParameter(self, id, prevId, idToPositionAfter) {
        //Remove current id from list
        uint nextIdInLine = self.list[id];
        self.list[prevId] = nextIdInLine;

        //Re-Add id in list:

        //Get the Id that should come after the milestone with idToPositionAfter
        nextIdInLine = self.list[idToPositionAfter];

        // Add id inbetween the targeted id (idToPositionAfter) and the originally following id (nextIdInLine)
        self.list[idToPositionAfter] = id;
        self.list[id] = nextIdInLine;

        //If _last doesnt point towards Sentinel
        if (self.list[self.last] != _SENTINEL) {
            //either id moved to last position
            if (self.list[id] == _SENTINEL) {
                self.last = id;
            }
            //or id moved away from last position
            else {
                self.last = prevId;
            }
        }
    }
}
