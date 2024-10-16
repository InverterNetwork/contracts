// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

interface IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1 is
    IRedeemingBondingCurveBase_v1,
    IBondingCurveBase_v1
{
    error IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1__InvalidDepositAmount(
    );

    function sellNative(uint _minAmountOut) external payable;
}
