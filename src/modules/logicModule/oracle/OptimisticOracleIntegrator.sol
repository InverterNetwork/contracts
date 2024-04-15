// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/console.sol";

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

import {IOptimisticOracleIntegrator} from
    "src/modules/logicModule/oracle/IOptimisticOracleIntegrator.sol";

// External Dependencies
import {OptimisticOracleV3CallbackRecipientInterface} from
    "src/modules/logicModule/oracle/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import {OptimisticOracleV3Interface} from
    "src/modules/logicModule/oracle/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import {ClaimData} from
    "src/modules/logicModule/oracle/optimistic-oracle-v3/ClaimData.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@oz/utils/introspection/ERC165Checker.sol";

abstract contract OptimisticOracleIntegrator is
    IOptimisticOracleIntegrator,
    Module
{
    using SafeERC20 for IERC20;

    //==========================================================================
    // Constants

    bytes32 public constant ASSERTER_ROLE = keccak256("DATA_ASSERTER");

    //==========================================================================
    // Storage

    // General Parameters
    IERC20 public defaultCurrency; // The currency used for the bond.
    OptimisticOracleV3Interface public oo; // The OptimisticOracleV3 instance where assertions will be published to.
    uint64 public assertionLiveness; // Time period an assertion is open for dispute (in seconds).
    bytes32 public defaultIdentifier; // The identifier used when creating the assertion. For most usecases, this will resolve to "ASSERT_TRUTH".

    // Assertion storage
    mapping(bytes32 => DataAssertion) public assertionData;

    //==========================================================================
    // Initialization

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external virtual override initializer {
        __Module_init(orchestrator_, metadata);

        (address currencyAddr, address ooAddr) =
            abi.decode(configData, (address, address));

        setDefaultCurrency(currencyAddr);
        setOptimisticOracle(ooAddr);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IOptimisticOracleIntegrator
    function getData(bytes32 assertionId) public view returns (bool, bytes32) {
        if (!assertionData[assertionId].resolved) return (false, 0);
        return (true, assertionData[assertionId].data);
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    function getAssertion(bytes32 assertionId)
        public
        view
        returns (DataAssertion memory)
    {
        return assertionData[assertionId];
    }

    //==========================================================================
    // Setter Functions

    /// @inheritdoc IOptimisticOracleIntegrator
    function setDefaultCurrency(address _newCurrency)
        public
        onlyOrchestratorOwner
    {
        if (address(_newCurrency) == address(0)) {
            revert Module__OptimisticOracleIntegrator__InvalidDefaultCurrency();
        }
        defaultCurrency = IERC20(_newCurrency);
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    function setOptimisticOracle(address _newOO) public onlyOrchestratorOwner {
        if (_newOO == address(0)) {
            revert Module__OptimisticOracleIntegrator__InvalidOOInstance();
        }
        //TODO  check interface support with ERC165Checker.supportsInterface()
        oo = OptimisticOracleV3Interface(_newOO);
        defaultIdentifier = oo.defaultIdentifier();
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    function setDefaultAssertionLiveness(uint64 _newLiveness)
        public
        onlyOrchestratorOwner
    {
        if (_newLiveness == 0) {
            revert Module__OptimisticOracleIntegrator__InvalidDefaultLiveness();
        }
        assertionLiveness = _newLiveness;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev Data can be asserted many times with the same combination of arguments, resulting in unique assertionIds. This is
    /// because the block.timestamp is included in the claim. The consumer contract must store the returned assertionId
    /// identifiers to able to get the information using getData.
    function assertDataFor(bytes32 dataId, bytes32 data, address asserter)
        public
        virtual
        onlyModuleRole(ASSERTER_ROLE)
        returns (bytes32 assertionId)
    {
        asserter = asserter == address(0) ? _msgSender() : asserter;
        uint bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(_msgSender(), address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);

        // The claim we want to assert is the first argument of assertTruth. It must contain all of the relevant
        // details so that anyone may verify the claim without having to read any further information on chain. As a
        // result, the claim must include both the data id and data, as well as a set of instructions that allow anyone
        // to verify the information in publicly available sources.
        // See the UMIP corresponding to the defaultIdentifier used in the OptimisticOracleV3 "ASSERT_TRUTH" for more
        // information on how to construct the claim.
        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Data asserted: 0x", // in the example data is type bytes32 so we add the hex prefix 0x.
                ClaimData.toUtf8Bytes(data),
                " for dataId: 0x",
                ClaimData.toUtf8Bytes(dataId),
                " and asserter: 0x",
                ClaimData.toUtf8BytesAddress(asserter),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            asserter,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            defaultCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );
        assertionData[assertionId] =
            DataAssertion(dataId, data, asserter, false);
        emit DataAsserted(dataId, data, asserter, assertionId);
    }

    //==========================================================================
    // Virtual Futcions to be overriden by Downstream Contracts

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev This updates status on local storage (or deletes the assertion if it was deemed false). Any additional functionalities can be appended by the inheriting contract.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public virtual {
        if (_msgSender() != address(oo)) {
            revert Module__OptimisticOracleIntegrator__CallerNotOO();
        }

        DataAssertion memory dataAssertion = assertionData[assertionId];

        emit DataAssertionResolved(
            assertedTruthfully,
            dataAssertion.dataId,
            dataAssertion.data,
            dataAssertion.asserter,
            assertionId
        );

        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            assertionData[assertionId].resolved = true;
        } else {
            delete assertionData[assertionId];
        } // Else delete the data assertion if it was false to save gas.
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public virtual;
}
