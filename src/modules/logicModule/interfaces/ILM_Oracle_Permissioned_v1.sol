// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";

/**
 * @title   Manual External Price Oracle Interface
 *
 * @notice  Interface for the manual price feed mechanism that allows setting
 *          and updating prices for token issuance and redemption operations.
 *
 * @dev     This interface extends IOraclePrice_v1 and adds functionality for
 *          manually setting prices. Both prices (issuance and redemption) must
 *          be non-zero values and can only be set by the contract owner.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  Zealynx Security
 */
interface ILM_Oracle_Permissioned_v1 is IOraclePrice_v1 {
    // -------------------------------------------------------------------------

    // Errors

    /// @notice Thrown when attempting to set a price to zero.
    error Module__LM_ExternalPriceSetter__InvalidPrice();

    // -------------------------------------------------------------------------
    // External Functions

    /// @notice Sets the issuance price for token issuance (buying tokens)
    ///         Price represents how much collateral is paid for 1 issuance token.
    /// @dev    Must be non-zero and denominated in collateral token decimals.
    ///         For example: With 6 decimal collateral token,
    ///         - To price 1 issuance token at 1.5 collateral, use 1_500_000
    ///         - To price 1 issuance token at 0.5 collateral, use 500_000
    /// @param  price_ The issuance price in collateral token decimals
    function setIssuancePrice(uint price_) external;

    /// @notice Sets the redemption price for token redemption (selling tokens)
    ///         Price represents how much collateral is returned for 1 issuance token.
    /// @dev    Must be non-zero and denominated in collateral token decimals.
    ///         For example: With 6 decimal collateral token,
    ///         - To price 1 issuance token at 1.5 collateral, use 1_500_000
    ///         - To price 1 issuance token at 0.5 collateral, use 500_000
    /// @param  price_ The redemption price in collateral token decimals
    function setRedemptionPrice(uint price_) external;

    /// @notice	Sets both issuance and redemption prices atomically, denominated
    ///         in the collateral token decimals.
    /// @dev    Both prices must be non-zero. Both the issuance and redemption
    ///         prices should be denominated in the collateral token decimals.
    ///         For example, if the collateral token has 6 decimals and the
    ///         issuance and redemption price are both 1.5, the issuancePrice_
    ///         and redemptionPrice_ parameters should be 1500000.
    /// @param	issuancePrice_ The issuance price to set, denominated in the
    ///         collateral token decimals.
    /// @param	redemptionPrice_ The redemption price to set, denominated in
    ///         the collateral token decimals.
    function setIssuanceAndRedemptionPrice(
        uint issuancePrice_,
        uint redemptionPrice_
    ) external;

    /// @notice	Gets the decimals of the collateral token.
    /// @dev    Decimals in which the issuance and redemption prices
    ///         are denominated.
    /// @return	decimals_ The decimals of the collateral token.
    function getCollateralTokenDecimals() external view returns (uint8);

    /// @notice Gets the price setter role identifier.
    /// @return bytes32 The PRICE_SETTER_ROLE identifier
    function getPriceSetterRole() external pure returns (bytes32);

    /// @notice Gets the price setter role admin identifier.
    /// @return bytes32 The PRICE_SETTER_ROLE_ADMIN identifier
    function getPriceSetterRoleAdmin() external pure returns (bytes32);
}
