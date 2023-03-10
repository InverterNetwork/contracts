// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

interface ISpecificFundingManager {
    //--------------------------------------------------------------------------
    // Types

    struct SpecificMilestoneFunding {
        uint fundingAmount;
        address[] funders;
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
        uint milestoneId, uint amount, address funder
    );

    /// @notice Event emitted when specific Milestone Funding gets added upon
    /// @notice amount is the new amount of the funding
    event SpecificMilestoneFundingAdded(
        uint milestoneId, uint amount, address funder
    );

    /// @notice Event emitted when specific Milestone Funding Amount gets withdrawn
    /// @notice amount is the new amount of the funding
    event SpecificMilestoneFundingWithdrawn(
        uint milestoneId, uint amount, address funder
    );

    /// @notice Event emitted when specific Milestone Funding gets fully removed
    /// @notice amount is the new amount of the funding
    event SpecificMilestoneFundingRemoved(
        uint milestoneId, uint amount, address funder
    );

    /// @notice Event emitted when specific Milestone Funding is collected by milestone
    event FundingCollected(uint milestoneId, uint amount);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // View Functions

    function getFunderAmountForMilestoneId(uint milestoneId)
        external
        view
        returns (uint);

    function getFunderAddressesForMilestoneId(uint milestoneId)
        external
        view
        returns (address[] memory);

    function getFundingAmountForMilestoneIdAndAddress(
        uint milestoneId,
        address funder
    ) external view returns (uint);

    //----------------------------------
    // Mutating Functions

    //Returns funding amount @todo
    function fundSpecificMilestone(uint milestoneId, uint addAmount)
        external
        returns (uint);

    function addToSpecificMilestoneFunding(uint milestoneId, uint addAmount)
        external
        returns (uint);

    function withdrawFromSpecificMilestoneFunding(
        uint milestoneId,
        uint withdrawAmount
    ) external returns (uint);

    function withdrawAllSpecificMilestoneFunding(uint milestoneId)
        external
        returns (uint);

    //----------------------------------
    // Collect funding Functions

    function collectFunding(uint milestoneId, uint amountNeeded)
        external
        returns (uint);
}
