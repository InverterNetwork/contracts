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

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

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
contract BondingCurveForwarder_v1 is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Events

    /// @notice Emitted when the bonding curve address is updated.
    event BondingCurveUpdated(
        address indexed oldBondingCurve, address indexed newBondingCurve
    );

    /// @notice Emitted when token approvals are updated.
    event ApprovalsUpdated(
        address indexed bondingCurve,
        address indexed collateralToken,
        address indexed issuanceToken
    );

    // -------------------------------------------------------------------------
    // Errors

    /// @notice The bonding curve address cannot be zero.
    error BondingCurveForwarder__InvalidBondingCurveAddress();

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

    // -------------------------------------------------------------------------
    // Constructor & Initializer

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the BondingCurveForwarder_v1 contract.
    /// @param _bondingCurve The address of the bonding curve contract.
    /// @param _owner The address of the contract owner.
    function initialize(address _bondingCurve, address _owner)
        external
        initializer
    {
        if (_bondingCurve == address(0)) {
            revert BondingCurveForwarder__InvalidBondingCurveAddress();
        }

        __Ownable_init(_owner);

        _setBondingCurve(_bondingCurve);
    }

    // -------------------------------------------------------------------------
    // Owner Functions

    /// @notice Updates the bonding curve address.
    /// @param _newBondingCurve The new bonding curve address.
    function updateBondingCurve(address _newBondingCurve) external onlyOwner {
        if (_newBondingCurve == address(0)) {
            revert BondingCurveForwarder__InvalidBondingCurveAddress();
        }

        address oldBondingCurve = address(restrictedBondingCurve);
        _setBondingCurve(_newBondingCurve);

        emit BondingCurveUpdated(oldBondingCurve, _newBondingCurve);
    }

    /// @notice Updates token approvals for the current bonding curve.
    function updateApprovals() external onlyOwner {
        _updateTokenApprovals();

        emit ApprovalsUpdated(
            address(restrictedBondingCurve),
            address(collateralToken),
            address(issuanceToken)
        );
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

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the bonding curve and updates token references and approvals.
    /// @param _bondingCurve The bonding curve address.
    function _setBondingCurve(address _bondingCurve) internal {
        restrictedBondingCurve =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(_bondingCurve);

        collateralToken = restrictedBondingCurve.token();
        issuanceToken =
            IERC20(IBondingCurveBase_v1(_bondingCurve).getIssuanceToken());

        _updateTokenApprovals();
    }

    /// @notice Updates token approvals for the current bonding curve.
    function _updateTokenApprovals() internal {
        collateralToken.approve(address(restrictedBondingCurve), type(uint).max);
        issuanceToken.approve(address(restrictedBondingCurve), type(uint).max);
    }
}
