// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Governor_v1} from "src/external/governance/Governor_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

contract Governor_v1_Exposed is Governor_v1 {
    function exposed_addBeaconToLinkedBeacons(IInverterBeacon_v1 beacon)
        external
    {
        _addBeaconToLinkedBeacons(beacon);
    }
}
