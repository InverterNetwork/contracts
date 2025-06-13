// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";

/**
 * @title   IFM_BC_Discrete_Redeeming_VirtualSupply_v1
 *
 * @notice  Interface for the Discrete Bonding Curve Funding Manager,
 *          managing token minting and redeeming based on discrete segments
 *          and tracking virtual supply.
 *
 * @dev     This interface defines the external functions and events for
 *          interacting with a discrete bonding curve funding manager that
 *          utilizes a virtual supply mechanism for redeeming.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
interface IFM_BC_Discrete_Redeeming_VirtualSupply_v1 {
    // =========================================================================
    // Structs

    /// @notice Struct to cache protocol fee data fetched from the FeeManager.
    struct ProtocolFeeCache {
        address collateralTreasury;
        address issuanceTreasury;
        uint collateralFeeBuyBps;
        uint issuanceFeeBuyBps;
        uint collateralFeeSellBps;
        uint issuanceFeeSellBps;
    }

    // =========================================================================
    // Errors

    /// @notice Thrown when a curve reconfiguration fails the invariance check.
    /// @param  newCalculatedReserve The collateral reserve calculated for the new segments.
    /// @param  currentVirtualCollateralSupply The current virtual collateral supply.
    error InvarianceCheckFailed(
        uint newCalculatedReserve, uint currentVirtualCollateralSupply
    );

    // =========================================================================
    // Events

    /// @notice Emitted when the bonding curve segments are set or updated.
    /// @param  segments The array of PackedSegment structs defining the bonding curve.
    event SegmentsSet(PackedSegment[] segments);

    // =========================================================================
    // Public - Getters

    /// @notice Returns the current configuration of the bonding curve segments.
    /// @return segments_ The array of PackedSegment structs defining the bonding curve.
    function getSegments()
        external
        view
        returns (PackedSegment[] memory segments_);

    // =========================================================================
    // Public - Mutating

    /// @notice Reconfigures the segments of the discrete bonding curve.
    /// @param  newSegments_ The new array of PackedSegment structs.
    function reconfigureSegments(PackedSegment[] memory newSegments_)
        external;

    /// @notice Sets the virtual collateral supply.
    /// @dev    Can only be called by the orchestrator admin.
    ///         Curve interactions (buy/sell) must be closed.
    /// @param  newSupply_ The new virtual collateral supply.
    function setVirtualCollateralSupply(uint newSupply_) external;

    /// @notice Returns the static price for buying one unit of the issuance token.
    /// @dev    This price is based on the current state of the curve and
    ///         the virtual collateral supply + 1.
    /// @return price_ The price to buy one unit.
    function getStaticPriceForBuying() external view returns (uint price_);

    /// @notice Returns the static price for selling one unit of the issuance token.
    /// @dev    This price is based on the current state of the curve and
    ///         the virtual issuance supply.
    /// @return price_ The price to sell one unit.
    function getStaticPriceForSelling() external view returns (uint price_);
}
