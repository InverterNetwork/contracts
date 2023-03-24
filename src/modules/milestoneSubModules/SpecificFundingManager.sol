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

    modifier validWithdrawAmount(uint withdrawAmount, uint milestoneId) {
        if (
            milestoneIdFundingAmounts[milestoneId][_msgSender()]
                < withdrawAmount
        ) {
            revert Module__ISpecificFundingManager__InvalidWithdrawAmount();
        }
        _;
    }

    modifier allowanceHighEnough(uint spendingAmount) {
        uint allowance = __Module_proposal.token().allowance(
            address(_msgSender()), address(this)
        );

        if (allowance < spendingAmount) {
            revert Module__ISpecificFundingManager__AllowanceNotHighEnough();
        }
        _;
    }

    modifier fundingNotCollected(uint milestoneId) {
        if (milestoneIdToFundingAddresses[milestoneId].fundingCollected) {
            revert Module__ISpecificFundingManager__FundingAlreadyCollected();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    address public milestoneManager;

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

    /// @inheritdoc ISpecificFundingManager
    function getFunderAmountForMilestoneId(uint milestoneId)
        external
        view
        returns (uint)
    {
        return milestoneIdToFundingAddresses[milestoneId].fundingAmount;
    }

    /// @inheritdoc ISpecificFundingManager
    function getFunderAddressesForMilestoneId(uint milestoneId)
        external
        view
        returns (address[] memory)
    {
        return milestoneIdToFundingAddresses[milestoneId].funders;
    }

    /// @inheritdoc ISpecificFundingManager
    function getFundingAmountForMilestoneIdAndAddress(
        uint milestoneId,
        address funder
    ) external view returns (uint) {
        return milestoneIdFundingAmounts[milestoneId][funder];
    }

    //----------------------------------
    // Mutating Functions

    /// @inheritdoc ISpecificFundingManager
    function fundSpecificMilestone(uint milestoneId, uint addAmount)
        external
        fundingNotCollected(milestoneId)
        allowanceHighEnough(addAmount)
        validAmount(addAmount)
        returns (uint)
    {
        address funder = _msgSender();
        if (milestoneIdFundingAmounts[milestoneId][funder] == 0) {
            return initialFundSpecificMilestone(milestoneId, addAmount);
        } else {
            milestoneIdFundingAmounts[milestoneId][funder] += addAmount;
            milestoneIdToFundingAddresses[milestoneId].fundingAmount +=
                addAmount;

            uint newAmount = milestoneIdFundingAmounts[milestoneId][funder];

            __Module_proposal.token().transferFrom(
                funder, address(this), addAmount
            );

            emit SpecificMilestoneFundingAdded(milestoneId, newAmount, funder);

            return newAmount;
        }
    }

    /// @inheritdoc ISpecificFundingManager
    function withdrawSpecificMilestoneFunding(
        uint milestoneId,
        uint withdrawAmount
    )
        external
        validWithdrawAmount(withdrawAmount, milestoneId)
        validAmount(withdrawAmount)
        returns (uint)
    {
        address funder = _msgSender();
        if (milestoneIdFundingAmounts[milestoneId][funder] == withdrawAmount) {
            withdrawAllSpecificMilestoneFunding(milestoneId);
            return 0;
        } else {
            milestoneIdFundingAmounts[milestoneId][funder] -= withdrawAmount;
            milestoneIdToFundingAddresses[milestoneId].fundingAmount -=
                withdrawAmount;

            uint newAmount = milestoneIdFundingAmounts[milestoneId][funder];

            __Module_proposal.token().transfer(funder, withdrawAmount);

            emit SpecificMilestoneFundingWithdrawn(
                milestoneId, newAmount, funder
                );

            return newAmount;
        }
    }

    function initialFundSpecificMilestone(uint milestoneId, uint addAmount)
        private
        returns (uint)
    {
        address funder = _msgSender();
        milestoneIdToFundingAddresses[milestoneId].funders.push(funder); //@note Not checking for duplicates/ might wanna test this
        milestoneIdToFundingAddresses[milestoneId].fundingAmount += addAmount;

        milestoneIdFundingAmounts[milestoneId][funder] = addAmount;

        __Module_proposal.token().transferFrom(funder, address(this), addAmount);

        emit SpecificMilestoneFunded(milestoneId, addAmount, funder);

        return addAmount;
    }

    function withdrawAllSpecificMilestoneFunding(uint milestoneId) private {
        address funder = _msgSender();

        uint withdrawAmount = milestoneIdFundingAmounts[milestoneId][funder];

        milestoneIdFundingAmounts[milestoneId][funder] = 0;
        milestoneIdToFundingAddresses[milestoneId].fundingAmount -=
            withdrawAmount;

        removeFunder(milestoneId, funder);

        __Module_proposal.token().transfer(funder, withdrawAmount);

        emit SpecificMilestoneFundingRemoved(milestoneId, funder);
    }

    //----------------------------------
    // Collect funding Functions

    /// @inheritdoc ISpecificFundingManager
    function collectFunding(uint milestoneId, uint amountNeeded)
        external
        onlyMilestoneManagerAccess
        validAmount(amountNeeded)
        fundingNotCollected(milestoneId)
        returns (uint)
    {
        milestoneIdToFundingAddresses[milestoneId].fundingCollected = true;

        address[] memory funders =
            milestoneIdToFundingAddresses[milestoneId].funders;

        uint length = funders.length;

        //If we dont have any funders stop the collecting
        if (length == 0) {
            emit FundingCollected(milestoneId, 0, funders);
            return 0;
        }

        uint fundingAmount =
            milestoneIdToFundingAddresses[milestoneId].fundingAmount;

        if (fundingAmount > amountNeeded) {
            for (uint i = 0; i < length; i++) {
                //This sets the amount each funder has left after the funding is collected based on the percentage share they had of the fundingAmount
                milestoneIdFundingAmounts[milestoneId][funders[i]] = //@note Decimal optimization?
                milestoneIdFundingAmounts[milestoneId][funders[i]]
                    * amountNeeded / fundingAmount;
            }
            milestoneIdToFundingAddresses[milestoneId].fundingAmount -=
                amountNeeded;

            __Module_proposal.token().transfer(milestoneManager, amountNeeded);

            emit FundingCollected(milestoneId, amountNeeded, funders);
            return amountNeeded;
        } else {
            //Take all if fundingAmount is not higher than the amount needed
            for (uint i = 0; i < length; i++) {
                milestoneIdFundingAmounts[milestoneId][funders[i]] = 0;
            }
            milestoneIdToFundingAddresses[milestoneId].fundingAmount = 0;
            delete milestoneIdToFundingAddresses[milestoneId].funders;

            __Module_proposal.token().transfer(milestoneManager, fundingAmount);

            emit FundingCollected(milestoneId, fundingAmount, funders);
            return fundingAmount;
        }
    }

    //----------------------------------
    // Helper Functions

    function removeFunder(uint milestoneId, address funder) private {
        address[] memory fundersSearchArray =
            milestoneIdToFundingAddresses[milestoneId].funders;

        uint funderIndex = type(uint).max;

        uint length = fundersSearchArray.length;
        for (uint i; i < length; i++) {
            if (fundersSearchArray[i] == funder) {
                funderIndex = i;
                break;
            }
        }

        // assert(funderIndex != type(uint).max); //@note removeFounder Should never be used if address is not found in funder array -> Test internally

        //Unordered removal
        address[] storage funders =
            milestoneIdToFundingAddresses[milestoneId].funders;
        // Move the last element into the place to delete
        funders[funderIndex] = funders[length - 1];
        // Remove the last element
        funders.pop();
    }
}
