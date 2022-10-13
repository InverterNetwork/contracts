// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";

interface IModule {
    struct Metadata {
        uint majorVersion;
        // maybe string description?
        string gitURL; // @todo mp: Assumed to be the unique key.
            //           What if more than one module per repo?
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Module__CallerNotAuthorized();

    /// @notice Function is only callable by the proposal.
    error Module__OnlyCallableByProposal();

    /// @notice Function is not callable inside the module's context.
    error Module__WantProposalContext();

    /// @notice Given proposal address invalid.
    error Module__InvalidProposalAddress();

    /// @notice Given metadata invalid.
    error Module__InvalidMetadata();

    /// @notice Proposal callback triggered failed.
    /// @param funcSig The signature of the function called.
    error Module_ProposalCallbackFailed(string funcSig);

    //--------------------------------------------------------------------------
    // Functions

    // @todo mp: Function doc for `init()`.

    /// @dev Can be overriden in downstream contract.
    /// @dev Has to call `__Module_init()`.
    function init(
        IProposal proposal,
        Metadata memory metadata,
        bytes memory configdata
    ) external;

    /// @notice Returns the module's identifier.
    /// @dev The identifier is defined as the keccak256 hash of the module's
    ///      abi packed encoded major version and git url.
    /// @return The module's identifier.
    function identifier() external view returns (bytes32);

    /// @notice Returns the module's metadata info.
    /// @return The module's {Metadata} struct instance.
    function info() external view returns (Metadata memory);

    /// @notice Returns the module's {IProposal} proposal instance.
    /// @return The module's proposal.
    function proposal() external view returns (IProposal);

    /// @notice Pauses the module.
    /// @dev Only callable by authorized addresses.
    function pause() external;

    /// @notice Unpauses the module.
    /// @dev Only callable by authorized addresses.
    function unpause() external;
}
