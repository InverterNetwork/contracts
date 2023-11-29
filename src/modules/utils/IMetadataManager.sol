// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IMetadataManager {
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
    event ManagerMetadataUpdated(
        string name, address account, string twitterHandle
    );

    /// @notice Event emitted when the orchestrator metadata changed.
    event OrchestratorMetadataUpdated(
        string title,
        string descriptionShort,
        string descriptionLong,
        string[] externalMedias,
        string[] categories
    );

    /// @notice Event emitted when the team metadata changed.
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
