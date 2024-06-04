// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IMetadataManager_v1} from
    "src/modules/utils/interfaces/IMetadataManager_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

/**
 * @title   Metadata Management
 *
 * @notice  Manages metadata storage for the Inverter Network's orchestrator and its
 *          associated modules, allowing for a structured approach to store and retrieve
 *          metadata about various entities within the network.
 *
 * @dev     Provides functionalities to update and retrieve metadata for managers,
 *          orchestrators, and team members, ensuring data consistency and accessibility
 *          across the network. This setup promotes a unified interface for metadata
 *          management across different network components.
 *
 * @author  Inverter Network
 */
contract MetadataManager_v1 is IMetadataManager_v1, Module_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IMetadataManager_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

    ManagerMetadata private _managerMetadata;
    OrchestratorMetadata private _orchestratorMetadata;
    MemberMetadata[] private _teamMetadata;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        (
            ManagerMetadata memory managerMetadata_,
            OrchestratorMetadata memory orchestratorMetadata_,
            MemberMetadata[] memory teamMetadata_
        ) = abi.decode(
            configData,
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
        onlyOrchestratorOwnerOrManager
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
    ) external onlyOrchestratorOwnerOrManager {
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
        onlyOrchestratorOwnerOrManager
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
