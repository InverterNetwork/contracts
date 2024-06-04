// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {OptimisticOracleV3CallbackRecipientInterface} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";

interface IOptimisticOracleIntegrator is
    OptimisticOracleV3CallbackRecipientInterface
{
    struct DataAssertion {
        bytes32 dataId; // The dataId that was asserted.
        bytes32 data; // This could be an arbitrary data type.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    //==========================================================================
    // Events

    event DataAsserted(
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    event DataAssertionResolved(
        bool assertedTruthfully,
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    //==========================================================================
    // Errors

    /// @notice Invalid default currency
    error Module__OptimisticOracleIntegrator__InvalidDefaultCurrency();

    /// @notice Invalid default liveness
    error Module__OptimisticOracleIntegrator__InvalidDefaultLiveness();

    /// @notice Invalid Optimistic Oracle instance
    error Module__OptimisticOracleIntegrator__InvalidOOInstance();

    /// @notice Caller is not Optimistic Oracle instance
    error Module__OptimisticOracleIntegrator__CallerNotOO();

    /// @notice Bond given for the specified currency is below minimum
    error Module__OptimisticOracleIntegrator__CurrencyBondTooLow();

    //==========================================================================
    // Functions

    // Getter Functions

    /// @notice For a given assertionId, returns a boolean indicating whether the data is accessible and the data itself.
    /// @param assertionId The id of the Assertion to return.
    /// @return bool Wether the assertion is resolved.
    /// @return bytes32 The Assertion Data.
    function getData(bytes32 assertionId)
        external
        view
        returns (bool, bytes32);

    /// @notice For a given assertionId, returns the assserion itself.
    /// @param assertionId The id of the Assertion to return.
    /// @return DataAssertion The Assertion.
    function getAssertion(bytes32 assertionId)
        external
        view
        returns (DataAssertion memory);

    // Setter Functions

    /// @notice Sets the default currency and amount for the bond.
    /// @param _newCurrency The address of the new default currency.
    /// @param _newBond The new bond amount.
    function setDefaultCurrencyAndBond(address _newCurrency, uint _newBond)
        external;

    /// @notice Sets the OptimisticOracleV3 instance where assertions will be published to.
    /// @param _newOO The address of the new OptimisticOracleV3 instance.
    function setOptimisticOracle(address _newOO) external;

    /// @notice Sets the default time assertions will be open for dispute.
    /// @param _newLiveness The new liveness in seconds.
    function setDefaultAssertionLiveness(uint64 _newLiveness) external;

    // State mutating functions

    /// @notice Asserts data for a specific dataId on behalf of an asserter address.
    /// @param dataId The id of the data to assert.
    /// @param data The data to assert.
    /// @param asserter The address doing the asserter. If zero defaults to _msgSender().
    /// @return assertionId The id of the generated Assertion.
    function assertDataFor(bytes32 dataId, bytes32 data, address asserter)
        external
        returns (bytes32 assertionId);
}
