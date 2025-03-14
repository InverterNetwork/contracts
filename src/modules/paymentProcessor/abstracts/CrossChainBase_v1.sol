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
 * @notice  Abstract base contract providing core cross-chain functionality for payment
 *          processors.
 * @dev     This contract exposes fundamental cross-chain operations and provides:
 *          - Bridge data storage and retrieval functionality
 *          - Abstract interface for bridge transfer execution
 *          - Integration with the Module_v1 base contract
 *          - Implementation of ICrossChainBase_v1 interface
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our
 *                          Security Policy at security.inverter.network or email us
 *                          directly!
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
        returns (bytes memory bridgeData_);

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Execute the cross-chain bridge transfer
    /// @dev    Override this function to implement specific bridge logic
    /// @param  order_ The payment order containing all necessary transfer details
    /// @return bridgeData_ Arbitrary data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) internal virtual returns (bytes memory bridgeData_);

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
