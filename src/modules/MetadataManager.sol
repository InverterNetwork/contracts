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

    ManagerMetadata private _managerMetadata;
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
            ManagerMetadata memory managerMetadata_,
            ProposalMetadata memory proposalMetadata_,
            MemberMetadata[] memory teamMetadata_
        ) = abi.decode(
            configdata, (ManagerMetadata, ProposalMetadata, MemberMetadata[])
        );

        _setManagerMetadata(managerMetadata_);

        _setProposalMetadata(proposalMetadata_);

        _setTeamMetadata(teamMetadata_);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    function getManagerMetadata()
        external
        view
        returns (ManagerMetadata memory)
    {
        return _managerMetadata;
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

    function setManagerMetadata(ManagerMetadata calldata managerMetadata_)
        external
        onlyAuthorizedOrManager
    {
        _setManagerMetadata(managerMetadata_);
    }

    function _setManagerMetadata(ManagerMetadata memory managerMetadata_)
        private
    {
        _managerMetadata = managerMetadata_;
        emit ManagerMetadataUpdated(
            managerMetadata_.name,
            managerMetadata_.account,
            managerMetadata_.twitterHandle
        );
    }

    function setProposalMetadata(ProposalMetadata calldata proposalMetadata_)
        public
        onlyAuthorizedOrManager
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
        onlyAuthorizedOrManager
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
