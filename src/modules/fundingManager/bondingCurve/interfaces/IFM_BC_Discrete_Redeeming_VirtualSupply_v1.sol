// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";

interface IFM_BC_Discrete_Redeeming_VirtualSupply_v1 {
    event SegmentsSet(PackedSegment[] segments);

    function getSegments() external view returns (PackedSegment[] memory);
}
