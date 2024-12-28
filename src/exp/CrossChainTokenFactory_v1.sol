// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Interfaces
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";

// External Dependencies
import {IMessageRecipient} from
    "../../lib/hyperlane-monorepo/solidity/contracts/interfaces/IMessageRecipient.sol";

// External Libraries
import {TokenMessage} from
    "../../lib/hyperlane-monorepo/solidity/contracts/token/libs/TokenMessage.sol";
import {TypeCasts} from
    "../../lib/hyperlane-monorepo/solidity/contracts/libs/TypeCasts.sol";

/**
 * @title   Cross Chain Token Factory
 * @notice  Handles cross-chain token deployment and management
 * @dev     Implements Hyperlane's IMessageRecipient for cross-chain messaging
 * @custom:security-contact security@inverter.network
 * @custom:version 1.0.0
 * @custom:inverter-standard-version 1.0.0
 * @author  Inverter Network
 */
contract CrossChainTokenFactory_v1 is IMessageRecipient {
    // =========================================================================
    // Libraries
    using TypeCasts for bytes32;
    using TypeCasts for address;
    using TokenMessage for bytes;

    // =========================================================================
    // Constants
    string private constant ERROR_INVALID_TOKEN = "Invalid token address";

    // =========================================================================
    // Storage
    /// @notice The issuance token contract address
    address private immutable _issuanceToken;

    /// @notice The funding manager contract address
    address private immutable _fundingManager;

    // =========================================================================
    // Events
    event MessageReceived(
        uint32 indexed origin_, bytes32 indexed sender_, bytes message_
    );

    // =========================================================================
    // Constructor
    /**
     * @notice Initializes the contract with the issuance token address
     * @param issuanceToken_ The address of the issuance token contract
     */
    constructor(address issuanceToken_) {
        require(issuanceToken_ != address(0), ERROR_INVALID_TOKEN);
        _issuanceToken = issuanceToken_;
    }

    // =========================================================================
    // External Functions - IMessageRecipient
    /**
     * @notice Handles incoming messages from other chains
     * @param origin_ The origin chain identifier
     * @param sender_ The sender's address on the origin chain
     * @param message_ The message payload
     */
    function handle(uint32 origin_, bytes32 sender_, bytes calldata message_)
        external
        payable
    {
        bytes32 recipient = message_.recipient();
        uint amount = message_.amount();
        bytes calldata metadata = message_.metadata();

        IERC20Issuance_v1(_issuanceToken).mint(
            recipient.bytes32ToAddress(), amount
        );

        emit MessageReceived(origin_, sender_, message_);
    }

    // =========================================================================
    // External Functions - View
    /**
     * @notice Gets the issuance token address
     * @return The issuance token address
     */
    function getIssuanceToken() external view returns (address) {
        return _issuanceToken;
    }

    /**
     * @notice Gets the funding manager address
     * @return The funding manager address
     */
    function getFundingManager() external view returns (address) {
        return _fundingManager;
    }
}
