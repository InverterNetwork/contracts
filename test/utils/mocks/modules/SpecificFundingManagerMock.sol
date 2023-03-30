// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

import {Module, IModule, IProposal} from "src/modules/base/Module.sol";

import {ISpecificFundingManager} from
    "src/modules/milestoneSubModules/ISpecificFundingManager.sol";

contract SpecificFundingManagerMock is ISpecificFundingManager, Module {
    ERC20Mock token;

    //--------------------------------------------------------------------------
    // Mock Functions

    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) public override(Module) initializer {
        __Module_init(proposal_, metadata);

        // Read first authorized address from configdata.
        address tokenAddress = abi.decode(configdata, (address));
        require(
            tokenAddress != address(0), "Zero address cant not be token Address"
        );

        token = ERC20Mock(tokenAddress);
    }

    function setFunding(uint amount) external {
        token.mint(address(this), amount);
    }

    //--------------------------------------------------------------------------
    // ISpecificFundingManager Functions

    function getFunderAmountForMilestoneId(uint)
        external
        pure
        returns (uint amount)
    {
        return 0;
    }

    function getFunderAddressesForMilestoneId(uint)
        external
        pure
        returns (address[] memory funders)
    {
        return new address[] (0);
    }

    function getFundingAmountForMilestoneIdAndAddress(uint, address)
        external
        pure
        returns (uint amount)
    {
        return 0;
    }

    //----------------------------------
    // Mutating Functions

    function fundSpecificMilestone(uint, uint) external pure returns (uint) {
        return 0;
    }

    function withdrawSpecificMilestoneFunding(uint, uint)
        external
        pure
        returns (uint)
    {
        return 0;
    }

    //----------------------------------
    // Collect funding Functions

    function collectFunding(uint, uint amountNeeded) external returns (uint) {
        uint funding = token.balanceOf(address(this));

        if (funding > amountNeeded) {
            token.transfer(msg.sender, amountNeeded);
            return amountNeeded;
        } else {
            token.transfer(msg.sender, funding);
            return funding;
        }
    }
}
