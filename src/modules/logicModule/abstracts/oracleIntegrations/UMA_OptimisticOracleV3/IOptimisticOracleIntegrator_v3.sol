// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {OptimisticOracleV3CallbackRecipientInterface} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";

/**
 * @title   Inverter Optimistic Oracle Integrator Interface
 *
 * @notice  This module allows for the integration of the UMA OptimisticOracleV3 contract with our modules.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @custom:version  v3.0.0
 *
 * @author  Inverter Network
 */
interface IOptimisticOracleIntegrator_v3 is
    OptimisticOracleV3CallbackRecipientInterface
{
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a data assertion.
    /// @param  dataId The dataId that was asserted.
    /// @param  data This could be an arbitrary data type.
    /// @param  asserter The address that made the assertion.
    /// @param  resolved Whether the assertion has been resolved.
    struct DataAssertion {
        bytes32 dataId;
        bytes32 data;
        address asserter;
        bool resolved;
    }

    //==========================================================================
    // Events

    /// @notice Event emitted when data is asserted.
    /// @param  dataId The dataId that was asserted.
    /// @param  data The data that was asserted.
    /// @param  asserter The address of the asserter.
    /// @param  assertionId The assertionId that was asserted.
    event DataAsserted(
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    /// @notice Event emitted when dataAssetiong is resolved.
    /// @param  assertedTruthfully Whether the assertion was resolved as true or false.
    /// @param  dataId The dataId that was asserted.
    /// @param  data The data that was asserted.
    /// @param  asserter The address of the asserter.
    /// @param  assertionId The assertionId that was asserted.
    event DataAssertionResolved(
        bool assertedTruthfully,
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    //==========================================================================
    // Errors

    /// @notice Invalid default currency.
    error Module__OptimisticOracleIntegrator_v3__InvalidDefaultCurrency();

    /// @notice Invalid default liveness.
    error Module__OptimisticOracleIntegrator_v3__InvalidDefaultLiveness();

    /// @notice Invalid Optimistic Oracle instance.
    error Module__OptimisticOracleIntegrator_v3__InvalidOOInstance();

    /// @notice Caller is not Optimistic Oracle instance.
    error Module__OptimisticOracleIntegrator_v3__CallerNotOO();

    /// @notice Bond given for the specified currency is below minimum.
    error Module__OptimisticOracleIntegrator_v3__CurrencyBondTooLow();

    /// @notice Asserter holds insufficient funds to pay for bond.
    error Module__OptimisticOracleIntegrator_v3_InsufficientFundsToPayForBond();

    //==========================================================================
    // Functions

    // Getter Functions

    /// @notice For a given assertionId, returns a boolean indicating whether the data is accessible
    ///         and the data itself.
    /// @param  assertionId The id of the Assertion to return.
    /// @return bool Wether the assertion is resolved.
    /// @return bytes32 The Assertion Data.
    function getData(bytes32 assertionId)
        external
        view
        returns (bool, bytes32);

    /// @notice For a given assertionId, returns the assserion itself.
    /// @param  assertionId The id of the Assertion to return.
    /// @return DataAssertion The Assertion.
    function getAssertion(bytes32 assertionId)
        external
        view
        returns (DataAssertion memory);

    // Setter Functions

    /// @notice Sets the default currency and amount for the bond.
    /// @dev    Function access controlled by authorizer.
    /// @param  _newCurrency The address of the new default currency.
    /// @param  _newBond The new bond amount.
    function setDefaultCurrencyAndBond(address _newCurrency, uint _newBond)
        external;

    /// @notice Sets the OptimisticOracleV3 instance where assertions will be published to.
    /// @dev    Function access controlled by authorizer.
    /// @param  _newOO The address of the new OptimisticOracleV3 instance.
    function setOptimisticOracle(address _newOO) external;

    /// @notice Sets the default time assertions will be open for dispute.
    /// @dev    Function access controlled by authorizer.
    /// @param  _newLiveness The new liveness in seconds.
    function setDefaultAssertionLiveness(uint64 _newLiveness) external;

    // State mutating functions

    /// @notice Asserts data for a specific dataId on behalf of an asserter address.
    /// @dev    Function access controlled by authorizer.
    /// @param  dataId The id of the data to assert.
    /// @param  data The data to assert.
    /// @param  asserter The address doing the asserter. If zero defaults to _msgSender().
    /// @return assertionId The id of the generated Assertion.
    function assertDataFor(bytes32 dataId, bytes32 data, address asserter)
        external
        returns (bytes32 assertionId);
}
