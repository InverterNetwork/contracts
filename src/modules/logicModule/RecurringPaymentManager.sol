// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

import {PaymentClient} from "src/modules/base/mixins/PaymentClient.sol";

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";
import {IRecurringPaymentManager} from
    "src/modules/logicModule/IRecurringPaymentManager.sol";

import {
    IPaymentClient,
    IPaymentProcessor
} from "src/modules/base/mixins/PaymentClient.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

contract RecurringPaymentManager is
    IRecurringPaymentManager,
    Module,
    PaymentClient
{
    using SafeERC20 for IERC20;
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
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);
        //Set empty list of RecurringPayment
        _paymentList.init();

        epochLength = abi.decode(configdata, (uint));

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
        onlyAuthorizedOrManager
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
        //
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
        onlyAuthorizedOrManager
    {
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

        //Amount of how many epochs have been not triggered
        uint epochsNotTriggered;

        //Amount of tokens in a single order
        uint orderAmount;

        //Amount of funds needed for all the recurring payment orders
        uint totalAmount;

        //Loop through every element in payment list until endId is reached
        while (currentId != endId) {
            RecurringPayment memory currentPayment = _paymentRegistry[currentId];

            //check if payment started
            if (currentPayment.startEpoch <= currentEpoch) {
                epochsNotTriggered =
                    currentEpoch - currentPayment.lastTriggeredEpoch;
                //If order hasnt been triggered this epoch
                if (epochsNotTriggered > 0) {
                    orderAmount = currentPayment.amount * epochsNotTriggered;
                    totalAmount += orderAmount;

                    _addPaymentOrder(
                        currentPayment.recipient,
                        orderAmount,
                        (currentEpoch + 1) * epochLength //End of current epoch to the lastTriggeredEpoch is the dueTo Date
                    );
                    //When done update the real state of lastTriggeredEpoch
                    _paymentRegistry[currentId].lastTriggeredEpoch =
                        currentEpoch;
                }
            }
            //Set to next Id in List
            currentId = _paymentList.list[currentId];
        }

        //ensure that this contract has enough tokens fulfill payments
        _ensureTokenBalance(totalAmount);

        //when done process the Payments correctly
        __Module_proposal.paymentProcessor().processPayments(
            IPaymentClient(address(this))
        );

        emit RecurringPaymentsTriggered(currentEpoch);
    }

    //--------------------------------------------------------------------------
    // {PaymentClient} Function Implementations

    function _ensureTokenBalance(uint amount)
        internal
        override(PaymentClient)
    {
        uint balance = __Module_proposal.token().balanceOf(address(this));

        if (balance < amount) {
            // Trigger callback from proposal to transfer tokens
            // to address(this).
            bool ok;
            (ok, /*returnData*/ ) = __Module_proposal.executeTxFromModule(
                address(__Module_proposal.fundingManager()),
                abi.encodeWithSignature(
                    "transferProposalToken(address,uint256)",
                    address(this),
                    amount - balance
                )
            );

            if (!ok) {
                revert Module__PaymentClient__TokenTransferFailed();
            }
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override(PaymentClient)
    {
        IERC20 token = __Module_proposal.token();
        uint allowance = token.allowance(address(this), address(spender));

        if (allowance < amount) {
            token.safeIncreaseAllowance(address(spender), amount - allowance);
        }
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor who)
        internal
        view
        override(PaymentClient)
        returns (bool)
    {
        return __Module_proposal.paymentProcessor() == who;
    }
}
