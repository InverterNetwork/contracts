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
import {IBountyManager} from "src/modules/logicModule/IBountyManager.sol";

import {
    IPaymentClient,
    IPaymentProcessor
} from "src/modules/base/mixins/PaymentClient.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

contract BountyManager is IBountyManager, Module, PaymentClient {
    using SafeERC20 for IERC20;
    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validId(uint bountyId) {
        if (!isExistingBountyId(bountyId)) {
            revert Module__BountyManager__InvalidBountyId();
        }
        _;
    }

    modifier validContributors(Contributor[] memory contributors) {
        uint length = contributors.length;
        if (length == 0) {
            revert Module__BountyManager__InvalidContributors();
        }
        address contrib;
        for (uint i; i < length; i++) {
            if (contributors[i].bountyAmount == 0) {
                revert Module__BountyManager__InvalidContributors();
            }
            contrib = contributors[i].addr;
            if (
                contrib == address(0) || contrib == address(this)
                    || contrib == address(proposal())
            ) {
                revert Module__BountyManager__InvalidContributors();
            }
        }

        _;
    }

    modifier notVerified(uint bountyId) {
        if (_bountyRegistry[bountyId].verified) {
            revert Module__BountyManager__BountyAlreadyVerified();
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

    /// @dev Registry mapping ids to Bounty structs.
    mapping(uint => Bounty) private _bountyRegistry;

    /// @dev List of Bounty id's.
    LinkedIdList.List _bountyList;
    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(IProposal proposal_, Metadata memory metadata, bytes memory)
        external
        override(Module)
        initializer
    {
        __Module_init(proposal_, metadata);
        //Set empty list of RecurringPayment
        _bountyList.init();
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IBountyManager
    function getBountyInformation(uint id)
        external
        view
        validId(id)
        returns (Bounty memory)
    {
        return _bountyRegistry[id];
    }

    /// @inheritdoc IBountyManager
    function listBountyIds() external view returns (uint[] memory) {
        return _bountyList.listIds();
    }

    /// @inheritdoc IBountyManager
    function getPreviousBountyId(uint id) external view returns (uint) {
        //@todo this is tied to if Bounties can be removed
        return _bountyList.getPreviousId(id);
    }

    /// @inheritdoc IBountyManager
    function isExistingBountyId(uint id) public view returns (bool) {
        return _bountyList.isExistingId(id);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IBountyManager
    function addBounty(
        Contributor[] calldata contributors,
        bytes calldata details
    )
        external
        //@todo restrict to appropriate role
        validContributors(contributors)
        returns (uint id)
    {
        // Note ids start at 1.
        uint bountyId = ++_nextId;

        // Add Bounty id to the list.
        _bountyList.addId(bountyId);

        Bounty storage b = _bountyRegistry[bountyId];

        // Add Bounty instance to registry.
        uint length = contributors.length;
        for (uint i; i < length; ++i) {
            b.contributors.push(contributors[i]);
        }

        b.details = details;

        emit BountyAdded(bountyId, contributors, details);

        return bountyId;
    }

    /// @inheritdoc IBountyManager
    function updateBounty(
        uint id,
        Contributor[] calldata contributors,
        bytes calldata details
    )
        external
        //@todo update access
        validId(id)
        validContributors(contributors)
    {
        Bounty storage b = _bountyRegistry[id];

        delete b.contributors;

        uint length = contributors.length; //@todo Do a seperate version for just updating contributors? gas inefficient
        for (uint i; i < length; ++i) {
            b.contributors.push(contributors[i]);
        }

        b.details = details;

        emit BountyUpdated(id, contributors, details);
    }

    //@todo keep that in?
    /* /// @inheritdoc IRecurringPaymentManager
    function removeRecurringPayment(uint prevId, uint id)
        external
        onlyAuthorizedOrManager
    {
        //Remove Id from list
        _paymentList.removeId(prevId, id);

        // Remove RecurringPayment instance from registry.
        delete _paymentRegistry[id];

        emit RecurringPaymentRemoved(id);
    } */

    /// @inheritdoc IBountyManager
    function verifyBounty(uint id) external validId(id) notVerified(id) 
    //@todo access
    {
        Contributor[] memory contribs = _bountyRegistry[id].contributors;

        uint length = contribs.length;

        //total amount needed to verifyBounty
        uint totalAmount;

        //current contributor in loop
        Contributor memory contrib;

        //For each Contributor add payments according to the bountyAmount specified
        for (uint i; i < length; i++) {
            contrib = contribs[i];
            totalAmount += contrib.bountyAmount;

            _addPaymentOrder(
                contrib.addr,
                contrib.bountyAmount,
                block.timestamp //dueTo Date is now
            );
        }

        //ensure that this contract has enough tokens to fulfill all payments
        _ensureTokenBalance(totalAmount);

        //when done process the Payments correctly
        __Module_proposal.paymentProcessor().processPayments(
            IPaymentClient(address(this))
        );

        //Set completed to true
        _bountyRegistry[id].verified = true;

        emit BountyVerified(id);
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
