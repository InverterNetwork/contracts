// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

/**
 * @title PackedSegment_v1
 * @notice Type-safe wrapper for packed segment data.
 * @dev Each PackedSegment represents the configuration for a single segment of a discrete bonding curve.
 * The data is packed into a bytes32 value to optimize gas costs for storage.
 *
 * Layout (256 bits total):
 * - numberOfSteps (16 bits): Maximum 65,535 steps.
 * - supplyPerStep (96 bits): Maximum ~7.9e28 (assuming 18 decimals for tokens).
 * - priceIncreasePerStep (72 bits): Maximum ~4.722e21 (assuming 18 decimals for price).
 * - initialPriceOfSegment (72 bits): Maximum ~4.722e21 (assuming 18 decimals for price).
 *
 * Offsets:
 * - initialPriceOfSegment: 0
 * - priceIncreasePerStep: 72
 * - supplyPerStep: 144
 * - numberOfSteps: 240
 */
type PackedSegment is bytes32;
