// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {LM_PC_Staking_v1} from "@lm/LM_PC_Staking_v1.sol";

contract LM_PC_Staking_v1AccessMock is LM_PC_Staking_v1 {
    //--------------------------------------------------------------------------
    // Getter Functions

    function getUserRewardValue(address user) external view returns (uint) {
        return userRewardValues[user];
    }

    function getUserRewards(address user) external view returns (uint) {
        return userRewards[user];
    }

    //--------------------------------------------------------------------------
    // Setter Functions

    function setRewardRate(uint rR) external {
        rewardRate = rR;
    }

    function setRewardValue(uint rV) external {
        rewardValue = rV;
    }

    function setLastUpdate(uint lU) external {
        lastUpdate = lU;
    }

    function setUserRewardValue(address user, uint rV) external {
        userRewardValues[user] = rV;
    }

    function setRewardsEnd(uint newRewardsEnd) external {
        rewardsEnd = newRewardsEnd;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function direct_update(address triggerAddress) external {
        _update(triggerAddress);
    }

    function direct_calculateRewardValue() external view returns (uint) {
        return _calculateRewardValue();
    }

    function direct_getRewardDistributionTimestamp()
        external
        view
        returns (uint)
    {
        return _getRewardDistributionTimestamp();
    }

    function direct_earned(address user, uint providedRewardValue)
        external
        view
        returns (uint)
    {
        return _earned(user, providedRewardValue);
    }

    function direct_distributeRewards(address recipient) external {
        _distributeRewards(recipient);
    }
}
