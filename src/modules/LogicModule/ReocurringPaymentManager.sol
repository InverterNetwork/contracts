// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

import {PaymentClient} from "src/modules/mixins/PaymentClient.sol";

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";
import {IReocurringPaymentManager} from
    "src/modules/LogicModule/IReocurringPaymentManager.sol";

import {
    IPaymentClient,
    IPaymentProcessor
} from "src/modules/mixins/PaymentClient.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

contract ReocurringPaymentManager is
    IReocurringPaymentManager,
    Module,
    PaymentClient
{
    using SafeERC20 for IERC20;
    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validId(uint reocurringPaymentId) {
        if (!isExistingReocurringPaymentId(reocurringPaymentId)) {
            revert Module__ReocurringPaymentManager__InvalidReocurringPaymentId(
            );
        }
        _;
    }

    modifier validStartEpoch(uint startEpoch) {
        if (getCurrentEpoch() > startEpoch) {
            revert Module__ReocurringPaymentManager__InvalidStartEpoch();
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

    /// @dev Registry mapping ids to ReocurringPayment structs.
    mapping(uint => ReocurringPayment) private _paymentRegistry;

    /// @dev List of ReocurringPayment id's.
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
        //Set empty list of ReocurringPayment
        _paymentList.init();

        epochLength = abi.decode(configdata, (uint));

        //revert if not at least 1 week and at most a year
        if (epochLength < 1 weeks && epochLength <= 52 weeks) {
            revert Module__ReocurringPaymentManager__EpochLengthToShort();
        }
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IReocurringPaymentManager
    function getEpochLength() external view returns (uint) {
        return epochLength;
    }

    /// @inheritdoc IReocurringPaymentManager
    function getReocurringPaymentInformation(uint id)
        external
        view
        validId(id)
        returns (ReocurringPayment memory)
    {
        return _paymentRegistry[id];
    }

    /// @inheritdoc IReocurringPaymentManager
    function listReocurringPaymentIds() external view returns (uint[] memory) {
        return _paymentList.listIds();
    }

    /// @inheritdoc IReocurringPaymentManager
    function isExistingReocurringPaymentId(uint id)
        public
        view
        returns (bool)
    {
        return _paymentList.isExistingId(id);
    }

    //--------------------------------------------------------------------------
    // Epoch Functions

    /// @inheritdoc IReocurringPaymentManager
    function getEpochFromTimestamp(uint timestamp)
        external
        view
        returns (uint epoch)
    {
        return timestamp / epochLength;
    }

    /// @inheritdoc IReocurringPaymentManager
    function getCurrentEpoch() public view returns (uint epoch) {
        return block.timestamp / epochLength;
    }

    /// @inheritdoc IReocurringPaymentManager
    function getFutureEpoch(uint xEpochsInTheFuture)
        external
        view
        returns (uint futureEpoch)
    {
        return getCurrentEpoch() + xEpochsInTheFuture;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IReocurringPaymentManager
    function addReocurringPayment(
        uint amount,
        uint startEpoch,
        address recipient
    )
        external
        validAmount(amount)
        validStartEpoch(startEpoch)
        validRecipient(recipient)
        returns (uint id)
    {
        // Note ids start at 1.
        uint reocurringPaymentId = ++_nextId;

        // Add ReocurringPayment id to the list.
        _paymentList.addId(reocurringPaymentId);

        // Add ReocurringPayment instance to registry.
        _paymentRegistry[reocurringPaymentId].amount = amount;
        _paymentRegistry[reocurringPaymentId].startEpoch = startEpoch;
        //
        _paymentRegistry[reocurringPaymentId].lastTriggeredEpoch =
            startEpoch - 1;

        _paymentRegistry[reocurringPaymentId].recipient = recipient;

        emit ReocurringPaymentAdded(
            reocurringPaymentId,
            amount,
            startEpoch,
            startEpoch - 1, //lastTriggeredEpoch
            recipient
        );

        return reocurringPaymentId;
    }

    /// @inheritdoc IReocurringPaymentManager
    function removeReocurringPayment(uint prevId, uint id) external {
        //Remove Id from list
        _paymentList.removeId(prevId, id);

        // Remove ReocurringPayment instance from registry.
        delete _paymentRegistry[id];

        emit ReocurringPaymentRemoved(id);
    }

    /// @inheritdoc IReocurringPaymentManager
    //@note @0xNuggan maybe include a triggerFor(startId,endId) function that allows you to trigger in intervals, to prevent runOutOfGas
    function trigger() external {
        //Get First Position in payment list
        uint currentId = _paymentList.getNextId(_SENTINEL);

        uint currentEpoch = getCurrentEpoch();

        //Loop through every element in payment list
        while (currentId != _SENTINEL) {
            ReocurringPayment memory currentPayment =
                _paymentRegistry[currentId]; //@todo Optimize?

            //check if payment started
            if (currentPayment.startEpoch <= currentEpoch) {
                //Catch up every not triggered epoch
                while (currentPayment.lastTriggeredEpoch != currentEpoch) {
                    _addPaymentOrder(
                        currentPayment.recipient,
                        currentPayment.amount,
                        (currentPayment.lastTriggeredEpoch + 1) * epochLength //End of next epoch to the lastTriggeredEpoch is the dueTo Date
                    );
                    currentPayment.lastTriggeredEpoch++;
                }

                //When done update the real state of lastTriggeredEpoch
                _paymentRegistry[currentId].lastTriggeredEpoch = currentEpoch;
            }
            //Set to next Id in List
            currentId = _paymentList.list[currentId];
        }

        //when done process the Payments correclty
        __Module_proposal.paymentProcessor().processPayments(
            IPaymentClient(address(this))
        );

        emit ReocurringPaymentsTriggered(currentEpoch);
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
                address(__Module_proposal.token()),
                abi.encodeWithSignature(
                    "transfer(address,uint256)", address(this), amount - balance
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
