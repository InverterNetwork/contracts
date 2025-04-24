// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @title   Oracle Price Interface
 *
 * @notice  Interface for oracle price feed calculations that provides a
 *          standardized way to query token prices for both issuance and
 *          redemption operations.
 *          way to query token prices for both issuance and redemption operations.
 *
 * @dev     Designed to facilitate various oracle price implementations. Each
 *          implementation must provide methods to get current prices for both
 *          buying (issuance) and selling (redemption) operations.
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
interface IOraclePrice_v1 {
    // -------------------------------------------------------------------------
    // Events

    /// @notice	Emitted when an issuance price is set.
    /// @param	price_ The price that was set.
    /// @param	caller_ The address that set the price.
    event IssuancePriceSet(uint indexed price_, address indexed caller_);

    /// @notice	Emitted when a redemption price is set.
    /// @param	price_ The price that was set.
    /// @param  caller_ The address that set the price.
    event RedemptionPriceSet(uint indexed price_, address indexed caller_);

    // -------------------------------------------------------------------------
    // Errors

    /// @notice	Thrown when price returned is zero.
    error OraclePrice__ZeroPrice();

    // -------------------------------------------------------------------------
    // External Functions
    /// @notice Gets current price for token issuance (buying tokens)
    ///         Price represents how much collateral is paid for 1 issuance token.
    /// @dev    Must be non-zero and denominated in collateral token decimals.
    ///         For example: With 6 decimal collateral token,
    ///         - To price 1 issuance token at 1.5 collateral, returns 1_500_000
    ///         - To price 1 issuance token at 0.5 collateral, returns 500_000
    /// @return price_ Current issuance price in collateral token decimals
    function getPriceForIssuance() external view returns (uint price_);

    /// @notice Gets current price for token redemption (selling tokens)
    ///         Price represents how much collateral is returned for 1 issuance token.
    /// @dev    Must be non-zero and denominated in collateral token decimals.
    ///         For example: With 6 decimal collateral token,
    ///         - To price 1 issuance token at 1.5 collateral, returns 1_500_000
    ///         - To price 1 issuance token at 0.5 collateral, returns 500_000
    /// @return price_ Current redemption price in collateral token decimals
    function getPriceForRedemption() external view returns (uint price_);
}
