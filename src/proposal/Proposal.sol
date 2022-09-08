
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@oz-up/security/PausableUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ModuleManager} from "src/proposal/base/ModuleManager.sol";

// Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

contract Proposal is IProposal, ModuleManager, PausableUpgradeable {
    //--------------------------------------------------------------------------
    // Errors

    error Proposal__CallerNotAuthorized();

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyAuthorized() {
        if (!authorizer.isAuthorized(msg.sender)) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The proposal's id.
    uint private _proposalId;

    /// @dev The list of funders.
    address[] private _funders;

    /// @notice The authorizer implementation used to authorize calls.
    IAuthorizer public override (IProposal) authorizer;

    //--------------------------------------------------------------------------
    // Public Functions

    function initialize(
        uint proposalId,
        address[] memory funders, // @todo mp: Make to calldata?
        address[] memory modules,
        IAuthorizer authorizer_
    )
        external
        initializer
    {
        _proposalId = proposalId;
        _funders = funders;

        __Pausable_init();
        __ModuleManager_init(modules);

        if (!isActiveModule(address(authorizer_))) {
            revert("Authorizer needs to be an active module");
        }

        authorizer = authorizer_;
    }

    /// @notice Executes a call on a target.
    /// @dev Only callable by authorized msg.sender.
    /// @param target The address to call.
    /// @param data The call data.
    function executeTx(address target, bytes memory data)
        external
        onlyAuthorized
        returns (bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) = target.call(data);

        if (!ok) {
            revert("executeTx: Call not ok");
        } else {
            return returnData;
        }
    }

    function version() external pure returns (string memory) {
        return "1";
    }
}
