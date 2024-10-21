// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1} from
    "./interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1.sol";
import {INativeIssuance_v1} from "@ex/token/INativeIssuance_v1.sol";

/**
 * @title   Inverter Bancor Redeeming Virtual Supply Bonding Curve Funding Manager for Native Tokens
 * @notice  This contract enables the issuance and redeeming of the Native Tokens using a Bancor-like bonding curve mechanism,
 *          but with the ability to redeem native tokens directly from the contract without needing ERC20 tokens.
 * @dev     Inherits {FM_BC_Bancor_Redeeming_VirtualSupply_v1}, {IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1}.
 *          Implements payable sell (redeeming) functionality for native tokens.
 *          The Issuance Token should be the {INativeIssuance_v1} token.
 * @author Inverter Network
 */
contract FM_BC_Bancor_Redeeming_VirtualSupply_Native_v1 is
    IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1,
    FM_BC_Bancor_Redeeming_VirtualSupply_v1
{
    function sellNative(uint _minAmountOut) public payable sellingIsEnabled {
        if (msg.value <= 0) {
            revert
                IFM_BC_Bancor_Redeeming_VirtualSupply_Native_v1__InvalidDepositAmount(
            );
        }

        INativeIssuance_v1(address(issuanceToken)).depositNative{
            value: msg.value
        }(_msgSender());

        sellTo(_msgSender(), msg.value, _minAmountOut);
    }
}
