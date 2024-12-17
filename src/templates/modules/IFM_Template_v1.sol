// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

/**
 * @title   Inverter Template Funding Manager
 *
 * @notice  Basic template for funding manager inteface used as base for developing new
 *          funding managers.
 *
 * @dev     This contract is used to showcase a basic setup for a funding
 *          manager. The contract showcases the following:
 *          - Inherit from the Module_v1 contract to enable interaction with
 *            the Inverter workflow.
 *          - Use of the IFundingManager_v1 interface to facilitate
 *            interaction as a Funding Manager.
 *          - Implement custom interface which has all the public facing
 *            functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state
 *            variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface
 *            support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
interface IFM_Template_v1 is IFundingManager_v1 {
    // =========================================================================
    // Structs

    // =========================================================================
    // Events

    /// @notice Emit when the token amount has been deposited.
    /// @param  sender_ The address of the depositor.
    /// @param  amount_ The amount of tokens deposited.
    event Deposited(address indexed sender_, uint amount_);

    // =========================================================================
    // Errors

    /// @notice Amount can not be zero.
    error Module__FM_Template_InvalidAmount();

    /// @notice Token receiver is not valid.
    error Module__FM_Template__ReceiverNotValid();

    // =========================================================================
    // Public - Getters

    /// @notice Returns the deposited balance of a specific address.
    /// @param  user_ The address of the user.
    /// @return amount_ Deposited amount of the user.
    function getDepositedAmount(address user_)
        external
        view
        returns (uint amount_);

    // =========================================================================
    // Public - Mutating

    /// @notice Deposits tokens to the funding manager.
    /// @param  amount_ The amount of tokens to deposit.
    function deposit(uint amount_) external;
}
