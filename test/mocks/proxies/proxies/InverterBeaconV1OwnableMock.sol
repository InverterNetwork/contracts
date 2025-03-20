pragma solidity ^0.8.0;

import {InverterBeaconV1Mock} from
    "test/utils/mocks/proxies/InverterBeaconV1Mock.sol";

import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {Context, Ownable} from "@oz/access/Ownable.sol";

contract InverterBeaconV1OwnableMock is InverterBeaconV1Mock, Ownable2Step {
    constructor(address owner) Ownable(owner) {
        // NO-OP
    }
}
