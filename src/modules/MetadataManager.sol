// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IMetadataManager} from "src/modules/IMetadataManager.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

contract MetadataManager is IMetadataManager, Module {
    //--------------------------------------------------------------------------
    // Storage

    ManagerMetadata private _managerMetadata;
    OrchestratorMetadata private _orchestratorMetadata;
    MemberMetadata[] private _teamMetadata;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        (
            ManagerMetadata memory managerMetadata_,
            OrchestratorMetadata memory orchestratorMetadata_,
            MemberMetadata[] memory teamMetadata_
        ) = abi.decode(
            configdata,
            (ManagerMetadata, OrchestratorMetadata, MemberMetadata[])
        );

        _setManagerMetadata(managerMetadata_);

        _setOrchestratorMetadata(orchestratorMetadata_);

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

    function getOrchestratorMetadata()
        external
        view
        returns (OrchestratorMetadata memory)
    {
        return _orchestratorMetadata;
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

    function setOrchestratorMetadata(
        OrchestratorMetadata calldata orchestratorMetadata_
    ) public onlyAuthorizedOrManager {
        _setOrchestratorMetadata(orchestratorMetadata_);
    }

    function _setOrchestratorMetadata(
        OrchestratorMetadata memory orchestratorMetadata_
    ) private {
        _orchestratorMetadata = orchestratorMetadata_;
        emit OrchestratorMetadataUpdated(
            orchestratorMetadata_.title,
            orchestratorMetadata_.descriptionShort,
            orchestratorMetadata_.descriptionLong,
            orchestratorMetadata_.externalMedias,
            orchestratorMetadata_.categories
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
