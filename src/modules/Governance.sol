// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";

contract Governance is Module {
    mapping(address => bool) private _authorized;

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);
    }

    /// @notice Returns whether the calling address is authorized to facilitate
    ///         the current transaction.
    function isAuthorized() external view returns (bool) {
        return _authorized[msg.sender];
    }

    /// @notice Adds a new address to the list of authorized addresses.
    function addToAuthorized(address who) external onlyAuthorized {
        _authorized[who] = true;
    }

    /// @notice Removes an address from the list of authorized addresses.
    function removeFromAuthorized(address who) external onlyAuthorized {
        _authorized[who] = false;
    }

    /*
        requiredQuorum() - Returns the number of confirmations that a certain action requires before it may be executed
        changeQuorum() - Updates the number of confirmations that a certain action requires before it may be executed
        confirmAction(action) - Confirms a queued action that has been initiated by another authorized address. It automatically executes the action if the quorum has been reached.
        cancelAction(action)
    */
}
