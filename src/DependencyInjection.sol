// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {Proposal} from "src/proposal/Proposal.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {ListAuthorizer} from "src/modules/authorizer/ListAuthorizer.sol";
import {SingleVoteGovernor} from "src/modules/authorizer/SingleVoteGovernor.sol";

contract DependencyInjection {

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Passed module name is invalid
    error DependencyInjection__InvalidModuleName();

    /// @notice Invalid proposal address to find the module address from
    error DependencyInjection__InvalidProposalAddress();

    /// @notice The given module is not used in the given proposal
    error DependencyInjection__ModuleNotUsedInProposal();

    string[] moduleList = [
        "ListAuthorizer",
        "SingleVoteGovernor",
        "PaymentClient",
        "RebasingFundingManager",
        "MilestoneManager",
        "RecurringPaymentManager",
        "SimplePaymentProcessor",
        "StreamingPaymentProcessor",
        "MetadataManager"
    ];

    function _isModuleNameValid(string calldata moduleName) private view returns(bool) {
        uint256 moduleListLength = moduleList.length;

        uint index;
        for(; index < moduleListLength; ) {
            // length comparison saves gas for each non-matching iteration
            if(bytes(moduleName).length == bytes(moduleList[index]).length) {
                if(keccak256(abi.encodePacked(moduleName)) == keccak256(abi.encodePacked(moduleList[index]))) {
                    return true;
                }
            }
            
            unchecked {
                ++index;
            }
        }

        // if the loop ended and the function did not terminate, that means the string was not present in the moduleList array.
        return false;
    }

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
        if(!(_isModuleNameValid(moduleName))) {
            revert DependencyInjection__InvalidModuleName();
        }

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

        try listAuthorizer.getAmountAuthorized() returns(uint) {
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
}