// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {OptimisticOracleV3CallbackRecipientInterface} from
    "src/modules/logicModule/oracle/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";

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

    //==========================================================================
    // Functions

    // Getter Functions

    /// @notice For a given assertionId, returns a boolean indicating whether the data is accessible and the data itself.
    /// @param assertionId The id of the Assertion to return.
    /// @return bool Wether the assertion is resolved.
    /// @return bytes32 The aAssertion Data.
    function getData(bytes32 assertionId) external returns (bool, bytes32);

    // Setter Functions

    /// @notice Sets the default currency for the bond.
    /// @param _newCurrency The address of the new default currency.
    function setDefaultCurrency(address _newCurrency) external;

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

    /// @notice Callback function for the moment the OptimisticOracleV3 assertion resolves.
    /// @param assertionId The id of the Assertion generating the callback.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) external;

    /// @notice Callback function for the moment the OptimisticOracleV3 assertion is disputed.
    /// @param assertionId The id of the Assertion generating the callback.
    function assertionDisputedCallback(bytes32 assertionId) external;
}
