// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ILM_PC_RecurringPayments_v1} from
    "@lm/interfaces/ILM_PC_RecurringPayments_v1.sol";

import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

/**
 * @title   Recurring Payment Manager
 *
 * @notice  Facilitates the creation, management, and execution of scheduled recurring
 *          payments within the Inverter Network, allowing for systematic and timed
 *          financial commitments or subscriptions.
 *
 * @dev     Uses epochs to define the period of recurring payments and supports operations
 *          such as adding, removing, and triggering payments based on time cycles.
 *          Integrates with {ERC20PaymentClientBase_v1} for handling actual payment
 *          transactions.
 *
 * @author  Inverter Network
 */
contract LM_PC_RecurringPayments_v1 is
    ILM_PC_RecurringPayments_v1,
    ERC20PaymentClientBase_v1
{
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

    modifier validId(uint recurringPaymentId) {
        if (!isExistingRecurringPaymentId(recurringPaymentId)) {
            revert Module__LM_PC_RecurringPayments__InvalidRecurringPaymentId();
        }
        _;
    }

    modifier validStartEpoch(uint startEpoch) {
        if (getCurrentEpoch() > startEpoch) {
            revert Module__LM_PC_RecurringPayments__InvalidStartEpoch();
        }
        _;
    }

    modifier startIdBeforeEndId(uint startId, uint endId) {
        if (startId > endId) {
            revert Module__LM_PC_RecurringPayments__StartIdNotBeforeEndId();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the beginning of the list.
    uint internal constant _SENTINEL = type(uint).max;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Value for what the next id will be.
    uint private _nextId;

    /// @dev length of an epoch
    uint private epochLength;

    /// @dev Registry mapping ids to RecurringPayment structs.
    mapping(uint => RecurringPayment) private _paymentRegistry;

    /// @dev List of RecurringPayment id's.
    LinkedIdList.List _paymentList;

    // Storage gap for future upgrades
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
        //Set empty list of RecurringPayment
        _paymentList.init();

        epochLength = abi.decode(configData, (uint));

        //revert if not at least 1 week and at most a year
        if (epochLength < 1 weeks || epochLength > 52 weeks) {
            revert Module__LM_PC_RecurringPayments__InvalidEpochLength();
        }
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
        onlyOrchestratorOwnerOrManager
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
            startEpoch - 1, //lastTriggeredEpoch
            recipient
        );

        return recurringPaymentId;
    }

    /// @inheritdoc ILM_PC_RecurringPayments_v1
    function removeRecurringPayment(uint prevId, uint id)
        external
        onlyOrchestratorOwnerOrManager
    {
        //trigger to resolve the given Payment
        _triggerFor(id, _paymentList.getNextId(id));

        //Remove Id from list
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
        //in the loop in _triggerFor it wouldnt run through endId itself, so we take the position afterwards in the list
        _triggerFor(startId, _paymentList.getNextId(endId));
    }

    function _triggerFor(uint startId, uint endId) private {
        //Set startId to be the current position in List
        uint currentId = startId;

        uint currentEpoch = getCurrentEpoch();

        RecurringPayment memory currentPayment;
        //Amount of how many epochs have been not triggered
        uint epochsNotTriggered;

        //Loop through every element in payment list until endId is reached
        while (currentId != endId) {
            currentPayment = _paymentRegistry[currentId];

            //check if payment started
            if (currentPayment.startEpoch <= currentEpoch) {
                epochsNotTriggered =
                    currentEpoch - currentPayment.lastTriggeredEpoch;
                //If order hasnt been triggered this epoch
                if (epochsNotTriggered > 0) {
                    //add paymentOrder for this epoch
                    _addPaymentOrder(
                        PaymentOrder({
                            recipient: currentPayment.recipient,
                            amount: currentPayment.amount,
                            createdAt: block.timestamp,
                            //End of current epoch is the dueTo Date
                            dueTo: (currentEpoch + 1) * epochLength
                        })
                    );

                    //if past epochs have not been triggered
                    if (epochsNotTriggered > 1) {
                        _addPaymentOrder(
                            PaymentOrder({
                                recipient: currentPayment.recipient,
                                //because we already made a payment that for the current epoch
                                amount: currentPayment.amount
                                    * (epochsNotTriggered - 1),
                                createdAt: block.timestamp,
                                //Payment was already due so dueDate is start of this epoch which should already have passed
                                dueTo: currentEpoch * epochLength
                            })
                        );
                    }
                    //When done update the real state of lastTriggeredEpoch
                    _paymentRegistry[currentId].lastTriggeredEpoch =
                        currentEpoch;
                }
            }
            //Set to next Id in List
            currentId = _paymentList.list[currentId];
        }

        //when done process the Payments correctly
        emit RecurringPaymentsTriggered(currentEpoch);

        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v1(address(this))
        );
    }
}
