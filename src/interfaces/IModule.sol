// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IModule {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Module__CallerNotAuthorized();

    /// @notice Function is only callable by the proposal.
    error Module__OnlyCallableByProposal();

    /// @notice Given proposal address invalid.
    error Module__InvalidProposalAddress();

    /// @notice Function is not callable inside the module's context.
    error Module__WantProposalContext();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Pauses the module.
    /// @dev Only callable by authorized addresses.
    function pause() external;

    /// @notice Unpauses the module.
    /// @dev Only callable by authorized addresses.
    function unpause() external;

    // @todo mp: Extend IModule Interface.
    // function identifier() external;
    // function version() external;
}
