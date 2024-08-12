// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

/**
 * @title   Inverter Reverter
 *
 * @notice  Enables the Inverter beacon structure to return a predefined error message in case a paused contract is called.
 *
 * @dev     Reverts all transactions with a predefined error
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract InverterReverter_v1 {
    /// @notice The contract that the transactions was meant to interact with is paused.
    error InverterReverter__ContractPaused();

    fallback() external {
        revert InverterReverter__ContractPaused();
    }
}
