// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

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
interface ICrossChainBase_v1 {
    // -------------------------------------------------------------------------
    // View Functions

    /// @notice Get the bridge data for a given payment ID.
    /// @param  paymentId_ The ID of the payment to get the bridge data for.
    /// @return bridgeData_ The bridge data for the given payment ID.
    function getBridgeData(uint paymentId_)
        external
        view
        returns (bytes memory bridgeData_);
}
