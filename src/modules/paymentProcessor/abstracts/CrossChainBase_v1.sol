// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {ICrossChainBase_v1} from "@pp/interfaces/ICrossChainBase_v1.sol";

// External
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Cross-chain Base Contract
 *
 * @notice  Abstract base contract providing core cross-chain functionality for payment
 *          processors. This contract serves as the foundation for implementing
 *          cross-chain payment processing capabilities.
 *
 * @dev     This contract exposes fundamental cross-chain operations and provides:
 *
 *          Key features:
 *              - Bridge Data Management
 *                Stores and retrieves bridge-specific data for each payment
 *
 *              - Extensible Bridge Interface
 *                Abstract bridge transfer execution for custom implementations
 *
 *              - Module Integration
 *                Seamless integration with the Module_v1 base contract
 *
 *              - Standard Compliance
 *                Full implementation of ICrossChainBase_v1 interface
 *
 * @custom:setup    This base contract requires the following implementation steps:
 *
 *                  1. Bridge Transfer Implementation:
 *                     - Purpose: Implement specific bridge transfer logic
 *                     - How:     Override _executeBridgeTransfer() function
 *                     - Example: function _executeBridgeTransfer(
 *                                 IERC20PaymentClientBase_v2.PaymentOrder memory order
 *                               ) internal override returns (bytes memory)
 *
 *                  2. Bridge Data Storage:
 *                     - Purpose: Store and manage bridge-specific transaction data
 *                     - How:     Utilize _bridgeData mapping for data persistence
 *                     - Access:  Via getBridgeData() public view function
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our
 *                          Security Policy at security.inverter.network or email us
 *                          directly!
 *
 * @custom:version 1.0.0
 *
 * @custom:standard-version 1.0.0
 *
 * @author  33Audits
 */
abstract contract CrossChainBase_v1 is ICrossChainBase_v1, Module_v1 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId_ == type(ICrossChainBase_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // -------------------------------------------------------------------------
    // State Variables

    /// @notice Mapping of payment IDs to bridge data.
    mapping(uint paymentId => bytes bridgeData) internal _bridgeData;

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc ICrossChainBase_v1
    function getBridgeData(uint paymentId_)
        public
        view
        virtual
        returns (bytes memory bridgeData_)
    {
        return _bridgeData[paymentId_];
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Execute the cross-chain bridge transfer.
    /// @dev    Override this function to implement specific bridge logic.
    /// @param  order_ The payment order containing all necessary transfer details.
    /// @return bridgeData_ Arbitrary data returned by the bridge implementation.
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) internal virtual returns (bytes memory bridgeData_);

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
