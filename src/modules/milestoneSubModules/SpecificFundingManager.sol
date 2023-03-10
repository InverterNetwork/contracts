// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {ISpecificFundingManager} from
    "src/modules/milestoneSubModules/ISpecificFundingManager.sol";

import {IProposal} from "src/proposal/IProposal.sol";

import {IMilestoneManager} from "src/modules/IMilestoneManager.sol";

import {Module, ContextUpgradeable} from "src/modules/base/Module.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract SpecificFundingManager is ISpecificFundingManager, Module {
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyMilestoneManagerAccess() {
        if (address(milestoneManager) != _msgSender()) {
            revert Module__ISpecificFundingManager__OnlyMilestoneManagerAccess();
        }
        _;
    }

    modifier validAmount(uint amount) {
        if (amount == 0) {
            revert Module__ISpecificFundingManager__InvalidAmount();
        }
        _;
    }

    modifier validWithdrawAmount(uint amount, uint milestoneId) {
        if (milestoneIdFundingAmounts[milestoneId][_msgSender()] < amount) {
            revert Module__ISpecificFundingManager__InvalidWithdrawAmount();
        }
        _;
    }

    modifier firstSpecificFunding(uint milestoneId) {
        if (milestoneIdFundingAmounts[milestoneId][_msgSender()] != 0) {
            revert Module__ISpecificFundingManager__NotFirstFunding();
        }
        _;
    }

    modifier fullWithdrawPossible(uint milestoneId) {
        if (milestoneIdFundingAmounts[milestoneId][_msgSender()] == 0) {
            revert Module__ISpecificFundingManager__FullWithdrawNotPossible();
        }
        _;
    }

    modifier allowanceHighEnough(uint spendingAmount) {
        IERC20 token = __Module_proposal.token();
        uint allowance = token.allowance(address(this), address(_msgSender()));

        if (allowance < spendingAmount) {
            revert Module__ISpecificFundingManager__AllowanceNotHighEnough();
        }
        _;
    }

    modifier fundingNotCollected(uint milestoneId) {
        if (!milestoneIdToFundingAddresses[milestoneId].fundingCollected) {
            revert Module__ISpecificFundingManager__FullWithdrawNotPossible();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    address milestoneManager;

    mapping(uint => SpecificMilestoneFunding) private
        milestoneIdToFundingAddresses;

    mapping(uint => mapping(address => uint)) private milestoneIdFundingAmounts;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);
        milestoneManager = abi.decode(configdata, (address));
    }

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // View Functions

    function getFunderAmountForMilestoneId(uint milestoneId)
        external
        view
        returns (uint)
    {
        return milestoneIdToFundingAddresses[milestoneId].fundingAmount;
    }

    function getFunderAddressesForMilestoneId(uint milestoneId)
        external
        view
        returns (address[] memory)
    {
        return milestoneIdToFundingAddresses[milestoneId].funders;
    }

    function getFundingAmountForMilestoneIdAndAddress(
        uint milestoneId,
        address funder
    ) external view returns (uint) {
        return milestoneIdFundingAmounts[milestoneId][funder];
    }

    //----------------------------------
    // Mutating Functions

    function fundSpecificMilestone(uint milestoneId, uint addAmount)
        public
        validAmount(addAmount)
        allowanceHighEnough(addAmount)
        firstSpecificFunding(milestoneId)
        returns (uint)
    {
        address funder = _msgSender();
        milestoneIdToFundingAddresses[milestoneId].funders.push(funder); //@note Not checking for duplicates/ might wanna test this
        milestoneIdToFundingAddresses[milestoneId].fundingAmount += addAmount;

        milestoneIdFundingAmounts[milestoneId][funder] = addAmount;

        __Module_proposal.token().transferFrom(funder, address(this), addAmount); //@note This is correct right?

        emit SpecificMilestoneFunded(milestoneId, addAmount, funder);

        return addAmount;
    }

    function addToSpecificMilestoneFunding(uint milestoneId, uint addAmount)
        external
        validAmount(addAmount)
        allowanceHighEnough(addAmount)
        returns (uint)
    {
        address funder = _msgSender();
        if (milestoneIdFundingAmounts[milestoneId][funder] == 0) {
            return fundSpecificMilestone(milestoneId, addAmount);
        } else {
            milestoneIdFundingAmounts[milestoneId][funder] += addAmount;
            milestoneIdToFundingAddresses[milestoneId].fundingAmount +=
                addAmount;

            uint newAmount = milestoneIdFundingAmounts[milestoneId][funder];

            __Module_proposal.token().transferFrom(
                funder, address(this), addAmount
            );

            emit SpecificMilestoneFundingAdded(
                milestoneId,
                newAmount, //@note maybe can optimize this via reference?
                funder
                );

            return newAmount;
        }
    }

    function withdrawFromSpecificMilestoneFunding(
        uint milestoneId,
        uint withdrawAmount
    )
        external
        validAmount(withdrawAmount)
        validWithdrawAmount(withdrawAmount, milestoneId)
        returns (uint)
    {
        address funder = _msgSender();
        if (milestoneIdFundingAmounts[milestoneId][funder] == withdrawAmount) {
            return withdrawAllSpecificMilestoneFunding(milestoneId);
        } else {
            milestoneIdFundingAmounts[milestoneId][funder] -= withdrawAmount;
            milestoneIdToFundingAddresses[milestoneId].fundingAmount -=
                addAmount;

            uint newAmount = milestoneIdFundingAmounts[milestoneId][funder];

            __Module_proposal.token().transfer(funder, withdrawAmount); //@note this should be correct right?

            emit SpecificMilestoneFundingWithdrawn(
                milestoneId,
                newAmount, //@note maybe can optimize this via reference?
                funder
                );

            return newAmount;
        }
    }

    function withdrawAllSpecificMilestoneFunding(uint milestoneId)
        public
        fullWithdrawPossible(milestoneId)
        returns (uint)
    {
        address funder = _msgSender();

        uint withdrawAmount = milestoneIdFundingAmounts[milestoneId][funder];

        milestoneIdFundingAmounts[milestoneId][funder] = 0;
        milestoneIdToFundingAddresses[milestoneId].fundingAmount -=
            withdrawAmount;

        removeFunder(milestoneId, funder);

        __Module_proposal.token().transfer(funder, withdrawAmount);

        emit SpecificMilestoneFundingRemoved(
            milestoneId, withdrawAmount, funder
            );

        return withdrawAmount;
    }

    //----------------------------------
    // Collect funding Functions

    function collectFunding(uint milestoneId, uint amountNeeded)
        external
        onlyMilestoneManagerAccess
        validAmount(amountNeeded)
        fundingNotCollected(milestoneId) //@note Is this modifier necessary? @0xNuggan
        returns (uint)
    {
        milestoneIdToFundingAddresses[milestoneId].fundingCollected = true;

        address[] memory funders =
            milestoneIdToFundingAddresses[milestoneId].funders;

        uint length = funders.length;

        //If we dont have any funders stop the collecting
        if (length == 0) {
            emit FundingCollected(milestoneId, 0);
            return 0;
        }

        uint fundingAmount =
            milestoneIdToFundingAddresses[milestoneId].fundingAmount;

        if (fundingAmount > amountNeeded) {
            for (uint i = 0; i < length; i++) {
                //@todo set funder amounts to the actual amount left as discussed in chat
                //
                //-> milestoneIdFundingAmounts[milestoneId][funders[i]] = actual Amount;
            }

            __Module_proposal.token().transfer(milestoneManager, amountNeeded);

            emit FundingCollected(milestoneId, amountNeeded);
            return amountNeeded;
        } else {
            //Take all if fundingAmount is not higher than the amount needed
            for (uint i = 0; i < length; i++) {
                milestoneIdFundingAmounts[milestoneId][funders[i]] = 0;
            }

            __Module_proposal.token().transfer(milestoneManager, fundingAmount); //@note probably not the correct deposit address @0xNuggan

            emit FundingCollected(milestoneId, fundingAmount);
            return fundingAmount;
        }
    }

    //----------------------------------
    // Helper Functions

    function removeFunder(uint milestoneId, address funder) private {
        address[] storage funders =
            milestoneIdToFundingAddresses[milestoneId].funders;

        uint funderIndex = type(uint).max;

        uint length = funders.length;
        for (uint i; i < length; i++) {
            if (funders[i] == funder) {
                funderIndex = i;
                break;
            }
        }

        assert(funderIndex != type(uint).max); //@note removeFounder Should never be used if address is not found in funder array -> Should this line be removed @0xNuggan?

        //Unordered removal

        // Move the last element into the place to delete
        funders[funderIndex] = funders[length - 1];
        // Remove the last element
        funders.pop();
    }
}
