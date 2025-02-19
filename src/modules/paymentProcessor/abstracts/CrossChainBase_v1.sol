// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";
import {ICrossChainBase_v1} from "../interfaces/ICrosschainBase_v1.sol";

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
 * @custom:standard-version 1.0.0
 * @author  33Audits
 */
abstract contract CrossChainBase_v1 is ICrossChainBase_v1, Module_v1 {
    // Storage Variables
    mapping(uint => bytes) internal _bridgeData;

    // External Functions
    /// @notice Process payments for a given payment client
    /// @param client The payment client to process payments for
    function processPayments(IERC20PaymentClientBase_v2 client)
        external
        virtual;

    // Public Functions
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

    /// @notice Get the bridge data for a given payment ID
    /// @param paymentId The ID of the payment to get the bridge data for
    /// @return The bridge data for the given payment ID
    function getBridgeData(uint paymentId)
        public
        view
        virtual
        returns (bytes memory);

    // Internal Functions
    /// @notice Execute the cross-chain bridge transfer
    /// @dev Override this function to implement specific bridge logic
    /// @param order The payment order containing all necessary transfer details
    /// @return bridgeData Arbitrary data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        bytes memory executionData
    ) internal virtual returns (bytes memory);
}
