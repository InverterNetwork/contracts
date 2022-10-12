// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";

interface IProposalFactory {
    error ProposalFactory__ModuleDataLengthMismatch();

    function target() external view returns (address);
    function moduleFactory() external view returns (address);

    function createProposal(
        address[] calldata funders,
        // Authorizer module arguments
        IModule.Metadata memory authorizerMetadata,
        bytes memory authorizerConfigdata,
        // Payer module arguments
        IModule.Metadata memory payerMetadata,
        bytes memory payerConfigdata,
        // Other module arguments
        IModule.Metadata[] memory moduleMetadatas,
        bytes[] memory moduleConfigdatas
    ) external returns (address);
}
