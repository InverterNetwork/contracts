// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IMetadataManager} from "src/modules/IMetadataManager.sol";
import {IProposal} from "src/proposal/IProposal.sol";

contract MetadataManager is IMetadataManager, Module {
    //--------------------------------------------------------------------------
    // Storage

    OwnerMetadata private _ownerMetadata;
    ProposalMetadata private _proposalMetadata;
    MemberMetadata[] private _teamMetadata;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);

        (
            OwnerMetadata memory ownerMetadata_,
            ProposalMetadata memory proposalMetadata_,
            MemberMetadata[] memory teamMetadata_
        ) = abi.decode(
            configdata, (OwnerMetadata, ProposalMetadata, MemberMetadata[])
        );

        _setOwnerMetadata(ownerMetadata_);

        _setProposalMetadata(proposalMetadata_);

        _setTeamMetadata(teamMetadata_);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    function getOwnerMetadata() external view returns (OwnerMetadata memory) {
        return _ownerMetadata;
    }

    function getProposalMetadata()
        external
        view
        returns (ProposalMetadata memory)
    {
        return _proposalMetadata;
    }

    function getTeamMetadata()
        external
        view
        returns (MemberMetadata[] memory)
    {
        return _teamMetadata;
    }

    //--------------------------------------------------------------------------
    // Setter Functions

    function setOwnerMetadata(OwnerMetadata calldata ownerMetadata_)
        external
        onlyAuthorizedOrOwner
    {
        _setOwnerMetadata(ownerMetadata_);
    }

    function _setOwnerMetadata(OwnerMetadata memory ownerMetadata_) private {
        _ownerMetadata = ownerMetadata_;
        emit OwnerMetadataUpdated(
            ownerMetadata_.name,
            ownerMetadata_.account,
            ownerMetadata_.twitterHandle
            );
    }

    function setProposalMetadata(ProposalMetadata calldata proposalMetadata_)
        public
        onlyAuthorizedOrOwner
    {
        _setProposalMetadata(proposalMetadata_);
    }

    function _setProposalMetadata(ProposalMetadata memory proposalMetadata_)
        private
    {
        _proposalMetadata = proposalMetadata_;
        emit ProposalMetadataUpdated(
            proposalMetadata_.title,
            proposalMetadata_.descriptionShort,
            proposalMetadata_.descriptionLong,
            proposalMetadata_.externalMedias,
            proposalMetadata_.categories
            );
    }

    function setTeamMetadata(MemberMetadata[] calldata teamMetadata_)
        external
        onlyAuthorizedOrOwner
    {
        _setTeamMetadata(teamMetadata_);
    }

    function _setTeamMetadata(MemberMetadata[] memory teamMetadata_) private {
        delete _teamMetadata;

        uint len = teamMetadata_.length;
        for (uint i; i < len; ++i) {
            _teamMetadata.push(teamMetadata_[i]);
        }

        emit TeamMetadataUpdated(teamMetadata_);
    }
}
