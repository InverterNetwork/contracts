// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract EventHelpers {
    // note: returns the topic from the last log that matches the event signature
    // e.g. if you emit an event from a test before you invoke the SuT this will get you the emitted topci form the SuT
    function getEventTopic(
        bytes memory signature,
        Vm.Log[] memory logs,
        uint topicIndex
    ) external view returns (bool, bytes32) {
        bytes32 eventSignature = keccak256(signature);
        bytes32 topic;
        uint logIndex;
        uint counter;
        for (uint i = 0; i < logs.length; i++) {
            if (eventSignature == logs[i].topics[0]) {
                logIndex = i;
                counter++;
            }
        }

        return (counter > 0, logs[logIndex].topics[topicIndex]);
    }

    function getAddressFromTopic(bytes32 topic)
        external
        pure
        returns (address)
    {
        return address(uint160(uint(topic)));
    }
}
