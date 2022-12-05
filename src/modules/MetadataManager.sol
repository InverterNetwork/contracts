// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module, ContextUpgradeable} from "src/modules/base/Module.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Internal Interfaces

import {IMetadataManager} from "src/modules/IMetadataManager.sol";
import {IProposal} from "src/proposal/IProposal.sol";

contract MetadataManager is IMetadataManager, Module {
    using LibString for string;

    //--------------------------------------------------------------------------
    // Storage

    OwnerMetadata private ownerMetadata;
    ProposalMetadata private proposalMetadata;
    TeamMetadata private teamMetadata;
    IERC20 public fundingToken;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override (Module) initializer {
        __Module_init(proposal_, metadata);

        (
            OwnerMetadata memory _ownerMetadata,
            ProposalMetadata memory _proposalMetadata,
            TeamMetadata memory _teamMetadata,
            IERC20 _fundingToken
        ) = abi.decode(
            configdata, (OwnerMetadata, ProposalMetadata, TeamMetadata, IERC20)
        );

        _setOwnerMetadata(_ownerMetadata);

        _setProposalMetadata(_proposalMetadata);

        _setTeamMetadata(_teamMetadata);

        _setFundingToken(_fundingToken);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    function getOwnerMetadata() external view returns (OwnerMetadata memory) {
        return ownerMetadata;
    }

    function getProposalMetadata()
        external
        view
        returns (ProposalMetadata memory)
    {
        return proposalMetadata;
    }

    function getTeamMetadata() external view returns (TeamMetadata memory) {
        return teamMetadata;
    }

    //--------------------------------------------------------------------------
    // Setter Functions

    function setOwnerMetadata(OwnerMetadata calldata _ownerMetadata)
        external
        onlyAuthorizedOrOwner
    {
        _setOwnerMetadata(_ownerMetadata);
    }

    function _setOwnerMetadata(OwnerMetadata memory _ownerMetadata) private {
        ownerMetadata = _ownerMetadata;
        emit OwnerMetadataUpdated(
            _ownerMetadata.name,
            _ownerMetadata.account,
            _ownerMetadata.twitterHandle
            );
    }

    function setProposalMetadata(ProposalMetadata calldata _proposalMetadata)
        public
        onlyAuthorizedOrOwner
    {
        _setProposalMetadata(_proposalMetadata);
    }

    function _setProposalMetadata(ProposalMetadata memory _proposalMetadata)
        private
    {
        proposalMetadata = _proposalMetadata;
        emit ProposalMetadataUpdated(
            _proposalMetadata.title,
            _proposalMetadata.descriptionShort,
            _proposalMetadata.descriptionLong,
            _proposalMetadata.externalMedias,
            _proposalMetadata.categories
            );
    }

    function setTeamMetadata(TeamMetadata calldata _teamMetadata)
        external
        onlyAuthorizedOrOwner
    {
        _setTeamMetadata(_teamMetadata);
    }

    function _setTeamMetadata(TeamMetadata memory _teamMetadata) private {
        uint len = _teamMetadata.members.length;
        for (uint i = 0; i < len; i++) {
            teamMetadata.members.push(_teamMetadata.members[i]);
        }

        emit TeamMetadataUpdated(_teamMetadata.members);
    }

    function _setFundingToken(IERC20 _fundingToken) private {
        fundingToken = _fundingToken;
        emit FundingTokenUpdated(address(_fundingToken));
    }
}
