// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

interface IMetadataManager {
    //--------------------------------------------------------------------------
    // Types

    struct OwnerMetadata {
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

    struct TeamMetadata {
        MemberMetadata[] members;
    }

    struct MemberMetadata {
        string name;
        address account;
        string url;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the owner metadata changed.
    event OwnerMetadataUpdated(
        string indexed name,
        address indexed account,
        string indexed twitterHandle
    );

    /// @notice Event emitted when the proposal metadata changed.
    event ProposalMetadataUpdated(
        string indexed title,
        string indexed descriptionShort,
        string indexed descriptionLong,
        string[] externalMedias,
        string[] categories
    );

    /// @notice Event emitted when the team metadata changed.
    event TeamMetadataUpdated(MemberMetadata[] indexed members);

    /// @notice Event emitted when the fundingToken changed.
    event FundingTokenUpdated(address indexed fundingToken);
}
