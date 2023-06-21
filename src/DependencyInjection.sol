// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {Proposal} from "src/proposal/Proposal.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {ListAuthorizer} from "src/modules/authorizer/ListAuthorizer.sol";
import {SingleVoteGovernor} from "src/modules/authorizer/SingleVoteGovernor.sol";
import {PaymentClient} from "src/modules/base/mixins/PaymentClient.sol";
import {RebasingFundingManager} from "src/modules/fundingManager/RebasingFundingManager.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract DependencyInjection {

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Passed module name is invalid
    error DependencyInjection__InvalidModuleName();

    /// @notice Invalid proposal address to find the module address from
    error DependencyInjection__InvalidProposalAddress();

    /// @notice The given module is not used in the given proposal
    error DependencyInjection__ModuleNotUsedInProposal();

    function _isProposalAddressValid(address proposalAddress) private view returns(bool) {
        Proposal proposal = Proposal(proposalAddress);

        try proposal.manager() returns(address) {
            return true;
        } catch {
            return false;
        }
    }

    function _isModuleUsedInProposal(address proposalAddress, string calldata moduleName) private view returns (uint256, address) {
        Proposal proposal = Proposal(proposalAddress);
        
        address[] memory moduleAddresses = proposal.listModules();
        uint256 moduleAddressesLength = moduleAddresses.length;
        string memory currentModuleName;
        uint256 index;

        for(; index < moduleAddressesLength; ) {
            currentModuleName = IModule(moduleAddresses[index]).title();
            
            if(bytes(currentModuleName).length == bytes(moduleName).length){
                if(keccak256(abi.encodePacked(currentModuleName)) == keccak256(abi.encodePacked(moduleName))) {
                    return (index, moduleAddresses[index]);
                }
            }

            unchecked {
                ++index;
            }
        }

        return (type(uint256).max, address(0));

    }

    function findModuleAddressInProposal(address proposalAddress, string calldata moduleName) external view returns (address) {
        if(!(_isProposalAddressValid(proposalAddress))) {
            revert DependencyInjection__InvalidProposalAddress();
        }

        (uint256 moduleIndex, address moduleAddress) = _isModuleUsedInProposal(proposalAddress, moduleName);
        if( moduleIndex == type(uint256).max) {
            revert DependencyInjection__ModuleNotUsedInProposal();
        }

        return moduleAddress;
    }

    function verifyAddressIsListAuthorizerModule(address listAuthorizerAddress) external view returns (bool) {
        ListAuthorizer listAuthorizer = ListAuthorizer(listAuthorizerAddress);

        try listAuthorizer.getAmountAuthorized() returns(uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function verifyAddressIsSingleVoteGovernorModule(address singleVoteGovernorAddress) external view returns (bool) {
        SingleVoteGovernor singleVoteGovernor = SingleVoteGovernor(singleVoteGovernorAddress);

        try singleVoteGovernor.getReceipt(type(uint256).max, address(0)) returns(SingleVoteGovernor.Receipt memory) {
            return true;
        } catch {
            return false;
        }
    }

    function verifyAddressIsPaymentClient(address paymentClientAddress) external view returns(bool) {
        PaymentClient paymentClient = PaymentClient(paymentClientAddress);

        try paymentClient.outstandingTokenAmount() returns(uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function verifyAddressIsRebasingFundingManager(address rebasingFundingManagerAddress) external view returns(bool) {
        RebasingFundingManager rebasingFundingManager = RebasingFundingManager(rebasingFundingManagerAddress);

        try rebasingFundingManager.token() returns(IERC20) {
            return true;
        } catch {
            return false;
        }
    }
}