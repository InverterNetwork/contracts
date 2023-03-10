// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

interface ISpecificFundingManager {
    //--------------------------------------------------------------------------
    // Types

    struct SpecificMilestoneFunding {
        /// @dev The amount of funding for this specific Milestone
        uint fundingAmount;
        /// @dev array of addresses that deposited tokens for this specific milestone
        address[] funders;
        /// @dev Wether Funding was collected by the milestoneModule
        bool fundingCollected;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Access denied for wrong MilestoneManager Address
    error Module__ISpecificFundingManager__OnlyMilestoneManagerAccess();

    /// @notice Given milestoneId is invalid.
    error Module__ISpecificFundingManager__InvalidMilestoneId();

    /// @notice Given amount is invalid.
    error Module__ISpecificFundingManager__InvalidAmount();

    /// @notice Given withdraw Amount is higher than funding amount.
    error Module__ISpecificFundingManager__InvalidWithdrawAmount();

    /// @notice Can only use this function sender address has no funding deposited for this milestone
    error Module__ISpecificFundingManager__NotFirstFunding();

    /// @notice Cant withdraw because funding amount is zero.
    error Module__ISpecificFundingManager__FullWithdrawNotPossible();

    /// @notice The allowance for this token transferal is not high enough
    error Module__ISpecificFundingManager__AllowanceNotHighEnough();

    /// @notice Funding was already collected.
    error Module__ISpecificFundingManager__FundingAlreadyCollected();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when specific Milestone gets funded
    event SpecificMilestoneFunded(
        uint indexed milestoneId, uint indexed amount, address indexed funder
    );

    /// @notice Event emitted when specific Milestone Funding gets added upon
    /// @param amount is the new amount of the funding
    event SpecificMilestoneFundingAdded(
        uint indexed milestoneId, uint indexed amount, address indexed funder
    );

    /// @notice Event emitted when specific Milestone Funding Amount gets withdrawn
    /// @param amount is the new amount of the funding
    event SpecificMilestoneFundingWithdrawn(
        uint indexed milestoneId, uint indexed amount, address indexed funder
    );

    /// @notice Event emitted when specific Milestone Funding gets fully removed
    event SpecificMilestoneFundingRemoved(
        uint indexed milestoneId, address indexed funder
    );

    /// @notice Event emitted when specific Milestone Funding is collected by milestone
    /// @param amount Amount Collected from this module
    event FundingCollected(
        uint indexed milestoneId, uint indexed amount, address[] funders
    );

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // View Functions

    /// @notice Returns the amount of tokens all funders deposited for a milestone with id 'milestoneId'.
    /// @param milestoneId : The id of the milestone that the funders deposited to
    /// @return amount : amount of tokens the funders deposited
    function getFunderAmountForMilestoneId(uint milestoneId)
        external
        view
        returns (uint amount);

    /// @notice Returns the funder addresses that deposited for a milestone with id 'milestoneId'.
    /// @param milestoneId : The id of the milestone that the funder deposited to
    /// @return funders : The funder addresses that deposited tokens a specified milestone
    function getFunderAddressesForMilestoneId(uint milestoneId)
        external
        view
        returns (address[] memory funders);

    /// @notice Returns the amount of tokens a funder address deposited for a milestone with id 'milestoneId'.
    /// @param milestoneId : The id of the milestone that the funder deposited to
    /// @param funder : The address of a funder
    /// @return amount : amount of tokens the funder deposited
    function getFundingAmountForMilestoneIdAndAddress(
        uint milestoneId,
        address funder
    ) external view returns (uint amount);

    //----------------------------------
    // Mutating Functions

    /// @notice Fund a specified amount of tokens to the milestone with id 'id'.
    /// @param milestoneId : The id of the milestone that the funder wants to deposit to
    /// @param addAmount : amount of tokens the funder wants to deposit
    /// @return amount of tokens currently deposited
    function fundSpecificMilestone(uint milestoneId, uint addAmount)
        external
        returns (uint);

    function addToSpecificMilestoneFunding(uint milestoneId, uint addAmount)
        external
        returns (uint);
    /// @notice Withdraw a specified amount of tokens previously deposited from the milestone with id 'id'.
    /// @param milestoneId : The id of the milestone that the funder wants to withdraw from
    /// @param withdrawAmount : amount of tokens the funder wants to withdraw
    /// @return amount of tokens still deposited
    function withdrawSpecificMilestoneFunding(
        uint milestoneId,
        uint withdrawAmount
    ) external returns (uint);

    function withdrawAllSpecificMilestoneFunding(uint milestoneId)
        external
        returns (uint);

    //----------------------------------
    // Collect funding Functions

    /// @notice Collect a specified amount of tokens to be sent to the connected milestoneModule
    /// @param milestoneId : The id of the milestone for which th funds are collected
    /// @param amountNeeded : The amount of tokens that are needed to fund the milestone
    /// @return amount of tokens that were collected
    function collectFunding(uint milestoneId, uint amountNeeded)
        external
        returns (uint);
}
