// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

// Internal Dependencies
import {
    ERC20PaymentClient,
    Module
} from "src/modules/logicModule/paymentClient/ERC20PaymentClient.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IRecurringPaymentManager} from
    "src/modules/logicModule/IRecurringPaymentManager.sol";

import {
    IERC20PaymentClient,
    IPaymentProcessor
} from "src/modules/logicModule/paymentClient/ERC20PaymentClient.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

contract RecurringPaymentManager is
    IRecurringPaymentManager,
    ERC20PaymentClient
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClient)
        returns (bool)
    {
        return interfaceId == type(IRecurringPaymentManager).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validId(uint recurringPaymentId) {
        if (!isExistingRecurringPaymentId(recurringPaymentId)) {
            revert Module__RecurringPaymentManager__InvalidRecurringPaymentId();
        }
        _;
    }

    modifier validStartEpoch(uint startEpoch) {
        if (getCurrentEpoch() > startEpoch) {
            revert Module__RecurringPaymentManager__InvalidStartEpoch();
        }
        _;
    }

    modifier startIdBeforeEndId(uint startId, uint endId) {
        if (startId > endId) {
            revert Module__RecurringPaymentManager__StartIdNotBeforeEndId();
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

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);
        //Set empty list of RecurringPayment
        _paymentList.init();

        epochLength = abi.decode(configData, (uint));

        //revert if not at least 1 week and at most a year
        if (epochLength < 1 weeks || epochLength > 52 weeks) {
            revert Module__RecurringPaymentManager__InvalidEpochLength();
        }
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IRecurringPaymentManager
    function getEpochLength() external view returns (uint) {
        return epochLength;
    }

    /// @inheritdoc IRecurringPaymentManager
    function getRecurringPaymentInformation(uint id)
        external
        view
        validId(id)
        returns (RecurringPayment memory)
    {
        return _paymentRegistry[id];
    }

    /// @inheritdoc IRecurringPaymentManager
    function listRecurringPaymentIds() external view returns (uint[] memory) {
        return _paymentList.listIds();
    }

    /// @inheritdoc IRecurringPaymentManager
    function getPreviousPaymentId(uint id) external view returns (uint) {
        return _paymentList.getPreviousId(id);
    }

    /// @inheritdoc IRecurringPaymentManager
    function isExistingRecurringPaymentId(uint id) public view returns (bool) {
        return _paymentList.isExistingId(id);
    }

    //--------------------------------------------------------------------------
    // Epoch Functions

    /// @inheritdoc IRecurringPaymentManager
    function getEpochFromTimestamp(uint timestamp)
        external
        view
        returns (uint epoch)
    {
        return timestamp / epochLength;
    }

    /// @inheritdoc IRecurringPaymentManager
    function getCurrentEpoch() public view returns (uint epoch) {
        return block.timestamp / epochLength;
    }

    /// @inheritdoc IRecurringPaymentManager
    function getFutureEpoch(uint xEpochsInTheFuture)
        external
        view
        returns (uint futureEpoch)
    {
        return getCurrentEpoch() + xEpochsInTheFuture;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IRecurringPaymentManager
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

    /// @inheritdoc IRecurringPaymentManager
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

    /// @inheritdoc IRecurringPaymentManager
    function trigger() external {
        _triggerFor(_paymentList.getNextId(_SENTINEL), _SENTINEL);
    }

    /// @inheritdoc IRecurringPaymentManager
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
            IERC20PaymentClient(address(this))
        );
    }
}
