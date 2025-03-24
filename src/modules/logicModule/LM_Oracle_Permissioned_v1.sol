// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {ILM_Oracle_Permissioned_v1} from
    "@lm/interfaces/ILM_Oracle_Permissioned_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";

// External
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

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
contract LM_Oracle_Permissioned_v1 is ILM_Oracle_Permissioned_v1, Module_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return interfaceId == type(ILM_Oracle_Permissioned_v1).interfaceId
            || interfaceId == type(IOraclePrice_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Constants

    /// @notice Role identifier for accounts authorized to set prices.
    /// @dev    This role should be granted to trusted price feeders only.
    bytes32 private constant PRICE_SETTER_ROLE = "PRICE_SETTER_ROLE";

    /// @notice Role identifier for the admin authorized to assign the price
    ///         setter role.
    /// @dev    This role should be set as the role admin within the Authorizer
    ///         module.
    bytes32 private constant PRICE_SETTER_ROLE_ADMIN = "PRICE_SETTER_ROLE_ADMIN";

    // -------------------------------------------------------------------------
    // State Variables

    /// @notice The price for issuing tokens (in collateral token decimals)
    uint private _issuancePrice;

    /// @notice The price for redeeming tokens (in collateral token decimals)
    uint private _redemptionPrice;

    /// @notice Decimals of the collateral token (e.g., USDC with 6 decimals).
    /// @dev    This is the token used to pay/buy with.
    uint8 private _collateralTokenDecimals;

    // -------------------------------------------------------------------------
    // Initialization

    /// @notice The module's initializer function.
    /// @dev	CAN be overridden by downstream contract.
    /// @dev	MUST call `__Module_init()`.
    /// @param orchestrator_ The orchestrator contract.
    /// @param metadata_ The metadata of the module.
    /// @param configData_ The config data of the module, comprised of:
    ///     - address: collateralToken: The collateral token address.
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        // Decode collateral token address from configData_.
        (address collateralToken) = abi.decode(configData_, (address));

        // Store token decimals for price normalization.
        _collateralTokenDecimals = IERC20Metadata(collateralToken).decimals();
    }

    // -------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc ILM_Oracle_Permissioned_v1
    function setIssuancePrice(uint price_)
        external
        virtual
        onlyModuleRole(PRICE_SETTER_ROLE)
    {
        _setIssuancePrice(price_);
    }

    /// @inheritdoc ILM_Oracle_Permissioned_v1
    function setRedemptionPrice(uint price_)
        external
        virtual
        onlyModuleRole(PRICE_SETTER_ROLE)
    {
        _setRedemptionPrice(price_);
    }

    /// @inheritdoc ILM_Oracle_Permissioned_v1
    function setIssuanceAndRedemptionPrice(
        uint issuancePrice_,
        uint redemptionPrice_
    ) external virtual onlyModuleRole(PRICE_SETTER_ROLE) {
        _setIssuancePrice(issuancePrice_);
        _setRedemptionPrice(redemptionPrice_);
    }

    /// @inheritdoc ILM_Oracle_Permissioned_v1
    function getCollateralTokenDecimals()
        external
        view
        virtual
        returns (uint8)
    {
        return _collateralTokenDecimals;
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForIssuance() external view virtual returns (uint) {
        return _issuancePrice;
    }

    /// @inheritdoc IOraclePrice_v1
    function getPriceForRedemption() external view virtual returns (uint) {
        return _redemptionPrice;
    }

    /// @inheritdoc ILM_Oracle_Permissioned_v1
    function getPriceSetterRole() external pure virtual returns (bytes32) {
        return PRICE_SETTER_ROLE;
    }

    /// @inheritdoc ILM_Oracle_Permissioned_v1
    function getPriceSetterRoleAdmin()
        external
        pure
        virtual
        returns (bytes32)
    {
        return PRICE_SETTER_ROLE_ADMIN;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Internal function to set the issuance price
    /// @param price_ The price to set
    function _setIssuancePrice(uint price_) internal virtual {
        if (price_ == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();
        _issuancePrice = price_;
        emit IssuancePriceSet(price_, _msgSender());
    }

    /// @notice Internal function to set the redemption price
    /// @param price_ The price to set
    function _setRedemptionPrice(uint price_) internal virtual {
        if (price_ == 0) revert Module__LM_ExternalPriceSetter__InvalidPrice();
        _redemptionPrice = price_;
        emit RedemptionPriceSet(price_, _msgSender());
    }

    /// @dev    Storage gap for upgradeable contracts.
    uint[50] private __gap;
}
