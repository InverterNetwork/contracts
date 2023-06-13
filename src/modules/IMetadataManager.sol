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

    struct ProposalMetadata {
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

    /// @notice Event emitted when the proposal metadata changed.
    event ProposalMetadataUpdated(
        string title,
        string descriptionShort,
        string descriptionLong,
        string[] externalMedias,
        string[] categories
    );

    /// @notice Event emitted when the team metadata changed.
    event TeamMetadataUpdated(MemberMetadata[] members);
}
