// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IMetadataManager_v1 {
    //--------------------------------------------------------------------------
    // Types

    struct ManagerMetadata {
        string name;
        address account;
        string twitterHandle;
    }

    struct OrchestratorMetadata {
        string title;
        string descriptionShort;
        string descriptionLong;
        string[] externalMedias;
        string[] categories;
    }

    struct MemberMetadata {
        string name;
        address account;
        string url;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the owner metadata changed.
    /// @param name The name of the owner.
    /// @param account The account of the owner.
    /// @param twitterHandle The twitter handle of the owner.
    event ManagerMetadataUpdated(
        string name, address account, string twitterHandle
    );

    /// @notice Event emitted when the orchestrator metadata changed.
    /// @param title The title of the orchestrator.
    /// @param descriptionShort The short description of the orchestrator.
    /// @param descriptionLong The long description of the orchestrator.
    /// @param externalMedias The external medias of the orchestrator.
    /// @param categories The categories of the orchestrator.
    event OrchestratorMetadataUpdated(
        string title,
        string descriptionShort,
        string descriptionLong,
        string[] externalMedias,
        string[] categories
    );

    /// @notice Event emitted when the team metadata changed.
    /// @param members The members of the team.
    event TeamMetadataUpdated(MemberMetadata[] members);

    function getManagerMetadata()
        external
        view
        returns (ManagerMetadata memory);

    function getOrchestratorMetadata()
        external
        view
        returns (OrchestratorMetadata memory);

    function getTeamMetadata()
        external
        view
        returns (MemberMetadata[] memory);

    //--------------------------------------------------------------------------
    // Setter Functions

    function setManagerMetadata(ManagerMetadata calldata managerMetadata_)
        external;

    function setOrchestratorMetadata(
        OrchestratorMetadata calldata orchestratorMetadata_
    ) external;

    function setTeamMetadata(MemberMetadata[] calldata teamMetadata_)
        external;
}
