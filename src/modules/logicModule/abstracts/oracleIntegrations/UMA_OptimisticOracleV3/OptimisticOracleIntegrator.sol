// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOptimisticOracleIntegrator} from
    "src/modules/logicModule/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/IOptimisticOracleIntegrator.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {OptimisticOracleV3CallbackRecipientInterface} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import {OptimisticOracleV3Interface} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";

// External Dependencies
import {ClaimData} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/ClaimData.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Optimistic Oracle Integrator
 *
 * @notice This module allows for the integration of the UMA OptimisticOracleV3 contract with our modules.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author Inverter Network
 */
abstract contract OptimisticOracleIntegrator is
    IOptimisticOracleIntegrator,
    Module_v1
{
    using SafeERC20 for IERC20;

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IOptimisticOracleIntegrator).interfaceId
            || interfaceId
                == type(OptimisticOracleV3CallbackRecipientInterface).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //==========================================================================
    // Constants

    /// @dev	The role that is allowed to assert data.
    bytes32 public constant ASSERTER_ROLE = keccak256("DATA_ASSERTER");

    //==========================================================================
    // Storage

    // General Parameters

    /// @dev	The currency used for the bond.
    IERC20 public defaultCurrency;
    /// @dev	The bond used for the assertions. Must be higher or equal to the minimum bond of the currency used.
    uint public defaultBond;
    /// @dev	The OptimisticOracleV3 instance where assertions will be published to.
    OptimisticOracleV3Interface public oo;
    /// @dev	Time period an assertion is open for dispute (in seconds).
    uint64 public assertionLiveness;
    /// @dev	The identifier used when creating the assertion. For most usecases, this will resolve to "ASSERT_TRUTH".
    bytes32 public defaultIdentifier;
    /// @dev Assertion storage.
    mapping(bytes32 => DataAssertion) public assertionData;

    /// @dev	Storage gap for future upgrades
    uint[50] private __gap;

    //==========================================================================
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external virtual override initializer {
        __Module_init(orchestrator_, metadata);

        (address currencyAddr, uint bondAmount, address ooAddr, uint64 liveness)
        = abi.decode(configData, (address, uint, address, uint64));

        __OptimisticOracleIntegrator_init(
            currencyAddr, bondAmount, ooAddr, liveness
        );
    }

    function __OptimisticOracleIntegrator_init(
        address currencyAddr,
        uint bondAmount,
        address ooAddr,
        uint64 liveness
    ) internal onlyInitializing {
        _setOptimisticOracle(ooAddr);
        _setDefaultAssertionLiveness(liveness);
        _setDefaultCurrencyAndBond(currencyAddr, bondAmount);
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
    function setDefaultCurrencyAndBond(address _newCurrency, uint _newBond)
        public
        onlyOrchestratorAdmin
    {
        _setDefaultCurrencyAndBond(_newCurrency, _newBond);
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    function setOptimisticOracle(address _newOO) public onlyOrchestratorAdmin {
        _setOptimisticOracle(_newOO);
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    function setDefaultAssertionLiveness(uint64 _newLiveness)
        public
        onlyOrchestratorAdmin
    {
        _setDefaultAssertionLiveness(_newLiveness);
    }

    //==========================================================================
    // Internal Functions

    /// @dev	Sets the default currency and bond.
    /// @param _newCurrency Address of the new default currency.
    /// @param _newBond The new default bond.
    function _setDefaultCurrencyAndBond(address _newCurrency, uint _newBond)
        internal
    {
        if (address(_newCurrency) == address(0)) {
            revert Module__OptimisticOracleIntegrator__InvalidDefaultCurrency();
        }
        if (_newBond < oo.getMinimumBond(address(_newCurrency))) {
            revert Module__OptimisticOracleIntegrator__CurrencyBondTooLow();
        }

        defaultCurrency = IERC20(_newCurrency);
        defaultBond = _newBond;
    }

    /// @dev	Sets the OptimisticOracleV3 instance where assertions will be published to.
    /// @param _newOO The address of the new OptimisticOracleV3 instance.
    function _setOptimisticOracle(address _newOO) internal {
        if (_newOO == address(0)) {
            revert Module__OptimisticOracleIntegrator__InvalidOOInstance();
        }
        oo = OptimisticOracleV3Interface(_newOO);
        defaultIdentifier = oo.defaultIdentifier();
    }

    /// @dev	Sets the default assertion liveness.
    /// @param _newLiveness The new default assertion liveness.
    function _setDefaultAssertionLiveness(uint64 _newLiveness) internal {
        if (_newLiveness < 21_600) {
            // 21600 seconds = 6 hours
            revert Module__OptimisticOracleIntegrator__InvalidDefaultLiveness();
        }
        assertionLiveness = _newLiveness;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev	Data can be asserted many times with the same combination of arguments, resulting in unique assertionIds.
    ///         This is because the block.timestamp is included in the claim. The consumer contract must
    ///         store the returned assertionId identifiers to able to get the information using getData.
    function assertDataFor(bytes32 dataId, bytes32 data_, address asserter)
        public
        virtual
        onlyModuleRole(ASSERTER_ROLE)
        returns (bytes32 assertionId)
    {
        asserter = asserter == address(0) ? _msgSender() : asserter;
        if (asserter == address(this)) {
            // ensure we have enough balance
            if (defaultCurrency.balanceOf(address(this)) < defaultBond) {
                revert
                    Module__OptimisticOracleIntegrator_InsufficientFundsToPayForBond(
                );
            }
        } else {
            (bool success, bytes memory data) = address(defaultCurrency).call(
                abi.encodeWithSelector(
                    defaultCurrency.transferFrom.selector,
                    _msgSender(),
                    address(this),
                    defaultBond
                )
            );
            // require(success && (data.length == 0 || abi.decode(data, (bool))) && token.code.length != 0); -> taken
            //      over from SafeERC20 since we want to override the revert messsage

            if (
                !success || (data.length > 0 && !abi.decode(data, (bool)))
                    || address(defaultCurrency).code.length == 0
            ) {
                revert
                    Module__OptimisticOracleIntegrator_InsufficientFundsToPayForBond(
                );
            }
        }
        defaultCurrency.safeIncreaseAllowance(address(oo), defaultBond);

        // The claim we want to assert is the first argument of assertTruth. It must contain all of the relevant
        // details so that anyone may verify the claim without having to read any further information on chain. As a
        // result, the claim must include both the data id and data, as well as a set of instructions that allow anyone
        // to verify the information in publicly available sources.
        // See the UMIP corresponding to the defaultIdentifier used in the OptimisticOracleV3 "ASSERT_TRUTH" for more
        // information on how to construct the claim.
        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Data asserted: 0x", // in the example data is type bytes32 so we add the hex prefix 0x.
                ClaimData.toUtf8Bytes(data_),
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
            defaultBond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );
        assertionData[assertionId] =
            DataAssertion(dataId, data_, asserter, false);
        emit DataAsserted(dataId, data_, asserter, assertionId);
    }

    //==========================================================================
    // Virtual Futcions to be overridden by Downstream Contracts

    /// @inheritdoc OptimisticOracleV3CallbackRecipientInterface
    /// @dev	This updates status on local storage (or deletes the assertion if it was deemed false).
    ///         Any additional functionalities can be appended by the inheriting contract.
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

    /// @inheritdoc OptimisticOracleV3CallbackRecipientInterface
    /// @dev	This OptimisticOracleV3 callback function needs to be defined so the OOv3
    ///         doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public virtual;
}
