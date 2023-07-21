// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";

interface IProposalFactory {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given id is invalid.
    error ProposalFactory__InvalidId();

    /// @notice The module's data arrays length mismatch.
    error ProposalFactory__ModuleDataLengthMismatch();

    /// @notice The proposal owner is address(0)
    error ProposalFactory__ProposalOwnerIsInvalid();

    //--------------------------------------------------------------------------
    // Structs

    struct ProposalConfig {
        address owner;
        IERC20 token;
    }

    struct ModuleConfig {
        IModule.Metadata metadata;
        bytes configdata;
        bytes dependencydata;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Creates a new proposal with caller being the proposal's owner.
    /// @param proposalConfig The proposal's config data.
    /// @param authorizerConfig The config data for the proposal's {IAuthorizer}
    ///                         instance.
    /// @param paymentProcessorConfig The config data for the proposal's
    ///                               {IPaymentProcessor} instance.
    /// @param moduleConfigs Variable length set of optional module's config
    ///                      data.
    function createProposal(
        ProposalConfig memory proposalConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IProposal);

    /// @notice Returns the {IProposal} target implementation address.
    function target() external view returns (address);

    /// @notice Returns the {IModuleFactory} implementation address.
    function moduleFactory() external view returns (address);

    /// @notice Returns the {IProposal} address that corresponds to the given id.
    /// @param id The requested proposal's id.
    function getProposalByID(uint id) external view returns (address);

    /// @notice Returns the counter of the current proposal id
    function getProposalIDCounter() external view returns (uint);
}
