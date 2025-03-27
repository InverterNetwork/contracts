// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";

/**
 * @title   Manual External Price Oracle Implementation.
 *
 * @notice  This contract provides a manual price feed mechanism for token
 *          operations, allowing authorized users to set and update prices
 *          for both issuance (buying) and redemption (selling) operations.
 *
 * @dev     This contract inherits from:
 *          - ILM_Oracle_Permissioned_v1: Implementation interface.
 *          - IOraclePrice_v1: Oracle price interface.
 *          - Module_v1: Base module functionality.
 *
 *          Key features:
 *              - Two separate price feeds for issuance and redemption.
 *                The contract maintains two separate price feeds for issuance
 *                and redemption operations.
 *
 *              - Manual price setting.
 *                Prices are manually set by the price setter role and must be
 *                non-zero values.
 *
 *              - Price decimal denominations.
 *                Prices are always given as amount of collateral going in/coming
 *                out. Prices are denominated in collateral token decimals. For
 *                example:
 *                - To price issuing 1 token at 1.5 collateral with 6 decimal
 *                  collateral: 1_500_000
 *                - To price redeeming 1 token at 0.5 collateral with 6 decimal
 *                  collateral: 500_000
 *
 * @custom:setup   This module requires the following MANDATORY setup steps:
 *
 *                 1. Configure Price Setter Role:
 *                    - Purpose: The price setter role is authorized to set
 *                               prices for issuance and redemption operations.
 *                    - How:     The OrchestratorAdmin (or PRICE_SETTER_ROLE_ADMIN
 *                               if configured) must:
 *                               1. Retrieve the price setter role identifier.
 *                               2. Grant the role to desired addresses.
 *                    - Example: module.grantModuleRole(
 *                                module.getPriceSetterRole(),
 *                                operatorAddress
 *                               );
 *
 *                 OPTIONAL setup steps for enhanced administration:
 *
 *                 1. Custom Price Setter Role Admin:
 *                    - Purpose: Enables delegation of price setter role
 *                               management to a dedicated admin role instead of
 *                               relying on the OrchestratorAdmin. This allows
 *                               for more granular access control and operational
 *                               flexibility.
 *                    - How:     The OrchestratorAdmin must:
 *                               1. Generate the role IDs for both roles.
 *                               2. Transfer admin rights through the Authorizer.
 *                    - Example: authorizer.transferAdminRole(
 *                               authorizer.generateRoleId(
 *                                 moduleAddress,
 *                                 module.getPriceSetterRole()
 *                               ),
 *                               authorizer.generateRoleId(
 *                                 moduleAddress,
 *                                 module.getPriceSetterRoleAdmin()
 *                                )
 *                               );
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
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
