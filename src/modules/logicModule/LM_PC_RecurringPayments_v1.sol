// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ILM_PC_RecurringPayments_v1} from
    "@lm/interfaces/ILM_PC_RecurringPayments_v1.sol";
import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Internal Libraries
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

/**
 * @title   Inverter Recurring Payment Manager
 *
 * @notice  Facilitates the creation, management, and execution of scheduled recurring
 *          payments within the Inverter Network, allowing for systematic and timed
 *          financial commitments or subscriptions.
 *
 * @dev     Uses epochs to define the period of recurring payments and supports operations
 *          such as adding, removing, and triggering payments based on time cycles.
 *          Integrates with {ERC20PaymentClientBase_v1} for handling actual payment
 *          transactions. Note that it will use the token type stored in the FundingManager for the payments.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract LM_PC_RecurringPayments_v1 is
    ILM_PC_RecurringPayments_v1,
    ERC20PaymentClientBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v1)
        returns (bool)
    {
        return interfaceId == type(ILM_PC_RecurringPayments_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev	Checks if the given id is valid.
    /// @param  recurringPaymentId The id of the RecurringPayment to check.
    modifier validId(uint recurringPaymentId) {
        if (!isExistingRecurringPaymentId(recurringPaymentId)) {
            revert Module__LM_PC_RecurringPayments__InvalidRecurringPaymentId();
        }
        _;
    }

    /// @dev	Checks if the given startEpoch is valid.
    /// @param  startEpoch The startEpoch of the RecurringPayment to check.
    modifier validStartEpoch(uint startEpoch) {
        if (getCurrentEpoch() > startEpoch) {
            revert Module__LM_PC_RecurringPayments__InvalidStartEpoch();
        }
        _;
    }

    /// @dev	Checks if the startId is before the endId.
    /// @param  startId The startId of the RecurringPayment to check.
    /// @param  endId The endId of the RecurringPayment to check.
    modifier startIdBeforeEndId(uint startId, uint endId) {
        if (startId > endId) {
            revert Module__LM_PC_RecurringPayments__StartIdNotBeforeEndId();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev	Marks the beginning of the list.
    uint internal constant _SENTINEL = type(uint).max;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev	Value for what the next id will be.
    uint private _nextId;

    /// @dev	length of an epoch.
    uint private epochLength;

    /// @dev	Registry mapping ids to RecurringPayment structs id => RecurringPayment.
    mapping(uint => RecurringPayment) private _paymentRegistry;

    /// @dev	List of RecurringPayment id's.
    LinkedIdList.List _paymentList;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        // Set empty list of RecurringPayment
        _paymentList.init();

        // Set the epoch Data
        uint newEpochLength = abi.decode(configData, (uint));
        epochLength = newEpochLength;

        // revert if not at least 1 week and at most a year
        if (epochLength < 1 weeks || epochLength > 52 weeks) {
            revert Module__LM_PC_RecurringPayments__InvalidEpochLength();
        }

        emit EpochLengthSet(newEpochLength);

        // Set the flags for the PaymentOrders
        uint8[] memory flags = new uint8[](2); // The Module will use 2 flags
        flags[0] = 1; // start, flag_ID 1
        flags[1] = 3; // end, flag_ID 3

        __ERC20PaymentClientBase_v1_init(flags);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function getEpochLength() external view returns (uint) {
        return epochLength;
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function getRecurringPaymentInformation(uint id)
        external
        view
        validId(id)
        returns (RecurringPayment memory)
    {
        return _paymentRegistry[id];
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function listRecurringPaymentIds() external view returns (uint[] memory) {
        return _paymentList.listIds();
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function getPreviousPaymentId(uint id) external view returns (uint) {
        return _paymentList.getPreviousId(id);
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function isExistingRecurringPaymentId(uint id) public view returns (bool) {
        return _paymentList.isExistingId(id);
    }

    //--------------------------------------------------------------------------
    // Epoch Functions

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function getEpochFromTimestamp(uint timestamp)
        external
        view
        returns (uint epoch)
    {
        return timestamp / epochLength;
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function getCurrentEpoch() public view returns (uint epoch) {
        return block.timestamp / epochLength;
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function getFutureEpoch(uint xEpochsInTheFuture)
        external
        view
        returns (uint futureEpoch)
    {
        return getCurrentEpoch() + xEpochsInTheFuture;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function addRecurringPayment(
        uint amount,
        uint startEpoch,
        address recipient
    )
        external
        onlyOrchestratorAdmin
        validAmount(amount)
        validStartEpoch(startEpoch)
        validRecipient(recipient)
        returns (uint id)
    {
        // Note ids start at 1.
        uint recurringPaymentId = ++_nextId;

        // Add RecurringPayment id to the list.
        _paymentList.addId(recurringPaymentId);

        // Add RecurringPayment instance to registry.
        _paymentRegistry[recurringPaymentId].amount = amount;
        _paymentRegistry[recurringPaymentId].startEpoch = startEpoch;
        _paymentRegistry[recurringPaymentId].lastTriggeredEpoch = startEpoch - 1;
        _paymentRegistry[recurringPaymentId].recipient = recipient;

        emit RecurringPaymentAdded(
            recurringPaymentId,
            amount,
            startEpoch,
            startEpoch - 1, // lastTriggeredEpoch
            recipient
        );

        return recurringPaymentId;
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function removeRecurringPayment(uint prevId, uint id)
        external
        onlyOrchestratorAdmin
    {
        // trigger to resolve the given Payment
        _triggerFor(id, _paymentList.getNextId(id));

        // Remove Id from list
        _paymentList.removeId(prevId, id);

        // Remove RecurringPayment instance from registry.
        delete _paymentRegistry[id];

        emit RecurringPaymentRemoved(id);
    }

    //--------------------------------------------------------------------------
    // Trigger

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function trigger() external {
        _triggerFor(_paymentList.getNextId(_SENTINEL), _SENTINEL);
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function triggerFor(uint startId, uint endId)
        external
        validId(startId)
        validId(endId)
        startIdBeforeEndId(startId, endId)
    {
        // in the loop in _triggerFor it wouldnt run through endId itself, so we take the position
        // afterwards in the list
        _triggerFor(startId, _paymentList.getNextId(endId));
    }

    /// @dev	Triggers the given RecurringPayment.
    /// @param  startId The id of the first RecurringPayment to trigger.
    /// @param  endId The id of the last RecurringPayment to trigger.
    function _triggerFor(uint startId, uint endId) private {
        // Set startId to be the current position in List
        uint currentId = startId;

        uint currentEpoch = getCurrentEpoch();

        RecurringPayment memory currentPayment;
        // Amount of how many epochs have been not triggered
        uint epochsNotTriggered;

        // Loop through every element in payment list until endId is reached
        while (currentId != endId) {
            currentPayment = _paymentRegistry[currentId];

            // check if payment started
            if (currentPayment.startEpoch <= currentEpoch) {
                epochsNotTriggered =
                    currentEpoch - currentPayment.lastTriggeredEpoch;
                // If order hasnt been triggered this epoch
                if (epochsNotTriggered > 0) {
                    // assemble data array

                    bytes32 flags;
                    bytes32[] memory data;

                    {
                        bytes32[] memory paymentParameters = new bytes32[](2);
                        paymentParameters[0] = bytes32(block.timestamp);
                        paymentParameters[1] =
                            bytes32((currentEpoch + 1) * epochLength);

                        (flags, data) =
                            _assemblePaymentConfig(paymentParameters);
                    }

                    // add paymentOrder for this epoch
                    _addPaymentOrder(
                        PaymentOrder({
                            recipient: currentPayment.recipient,
                            paymentToken: address(
                                orchestrator().fundingManager().token()
                            ),
                            amount: currentPayment.amount,
                            originChainId: block.chainid,
                            targetChainId: block.chainid,
                            flags: flags,
                            data: data
                        })
                    );

                    // if past epochs have not been triggered
                    if (epochsNotTriggered > 1) {
                        data[1] = bytes32(currentEpoch * epochLength);
                        _addPaymentOrder(
                            PaymentOrder({
                                recipient: currentPayment.recipient,
                                paymentToken: address(
                                    orchestrator().fundingManager().token()
                                ),
                                amount: currentPayment.amount
                                    * (epochsNotTriggered - 1),
                                originChainId: block.chainid,
                                targetChainId: block.chainid,
                                flags: flags,
                                data: data
                            })
                        );
                    }
                    // When done update the real state of lastTriggeredEpoch
                    _paymentRegistry[currentId].lastTriggeredEpoch =
                        currentEpoch;
                }
            }
            // Set to next Id in List
            currentId = _paymentList.list[currentId];
        }

        // when done process the Payments correctly
        emit RecurringPaymentsTriggered(currentEpoch);

        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v1(address(this))
        );
    }
}
