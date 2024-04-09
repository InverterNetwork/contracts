pragma solidity ^0.8.0;

import {InverterBeaconMock} from
    "test/utils/mocks/factories/beacon/InverterBeaconMock.sol";

import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {Context, Ownable} from "@oz/access/Ownable.sol";

contract InverterBeaconOwnableMock is InverterBeaconMock, Ownable2Step {
    constructor(address owner) Ownable(owner) {
        // NO-OP
    }
}
