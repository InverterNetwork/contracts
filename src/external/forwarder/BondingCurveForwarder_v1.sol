// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies

import {
    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1
} from "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Restricted Bancor Virtual Supply Bonding Curve Funding Manager Call Forwarder
 *
 * @notice  This contract forwards calls to the Bancor Redeeming Virtual Supply
 *          Bonding Curve Funding Manager contract. It is used to allow public
 *          calls to the restricted bonding curve contract by granting it the
 *          CURVE_INTERACTION_ROLE.
 *
 * @dev     It forwards the `buy()`, `buyFor()`, `sell()` and `sellTo()` functions
 *          to the Bonding Curve contract.
 *
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.3
 *
 * @author  Inverter Network
 */
contract BondingCurveForwarder_v1 is Context {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Errors

    /// @notice The feature is deactivated in this implementation.
    error Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated(
    );

    // -------------------------------------------------------------------------
    // Storage

    /// @dev    The bonding curve contract.
    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 public
        restrictedBondingCurve;

    IERC20 public collateralToken;
    IERC20 public issuanceToken;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    constructor(address _bondingCurve) {
        restrictedBondingCurve =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(_bondingCurve);

        collateralToken = restrictedBondingCurve.token();
        collateralToken.approve(address(restrictedBondingCurve), type(uint).max);
        issuanceToken =
            IERC20(IBondingCurveBase_v1(_bondingCurve).getIssuanceToken());
        issuanceToken.approve(address(restrictedBondingCurve), type(uint).max);
    }

    // -------------------------------------------------------------------------
    // Public Functions

    function buy(uint _depositAmount, uint _minAmountOut) public {
        buyFor(_msgSender(), _depositAmount, _minAmountOut);
    }

    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
    {
        collateralToken.safeTransferFrom(
            _msgSender(), address(this), _depositAmount
        );
        restrictedBondingCurve.buyFor(_receiver, _depositAmount, _minAmountOut);
    }

    function sell(uint _depositAmount, uint _minAmountOut) public {
        sellTo(_msgSender(), _depositAmount, _minAmountOut);
    }

    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
    {
        issuanceToken.safeTransferFrom(
            _msgSender(), address(this), _depositAmount
        );
        restrictedBondingCurve.sellTo(_receiver, _depositAmount, _minAmountOut);
    }
}
