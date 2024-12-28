// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IMailbox} from
    "../../lib/hyperlane-monorepo/solidity/contracts/interfaces/IMailbox.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {TokenMessage} from
    "../../lib/hyperlane-monorepo/solidity/contracts/token/libs/TokenMessage.sol";
import {TypeCasts} from
    "../../lib/hyperlane-monorepo/solidity/contracts/libs/TypeCasts.sol";

/**
 * @title   Inverter Issuance Token Bridge
 * @notice  Enables Issuance Token to be bridged to another chain
 * @dev     Logic Module (LM) that interacts with Funding Manager (FM) to handle
 *          cross-chain token bridging operations
 * @custom:security-contact security@inverter.network
 * @custom:version 1.0.0
 * @custom:inverter-standard-version 1.0.0
 * @author  Inverter Network
 */
contract LM_FM_IssuanceTokenBridge_v1 is Module_v1 {
    // =========================================================================
    // Libraries
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Issuance_v1;
    using TypeCasts for address;

    // =========================================================================
    // Constants
    /// @notice Error messages for the contract
    string private constant ERROR_INVALID_DESTINATION = "Invalid destination";
    string private constant ERROR_INSUFFICIENT_AMOUNT = "Insufficient amount";
    string private constant ERROR_INVALID_ISSUANCE_TOKEN = "Invalid token";

    // =========================================================================
    // Storage
    /// @notice The issuance token contract address
    address private _issuanceToken;

    /// @notice The source chain ID
    uint private _sourceChainId;

    /// @notice Mapping of allowed destination addresses per chain ID (Mailbox)
    mapping(uint => address) private _allowedDestinations;

    mapping(uint => address) private _receivers;

    // =========================================================================
    // Events
    event DestinationAdded(
        uint indexed chainId_,
        address indexed destination_,
        address indexed receiver_
    );
    event TokensBridged(
        address indexed from_, uint indexed destinationChainId_, uint amount_
    );

    // =========================================================================
    // Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Module_v1.Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        _sourceChainId = block.chainid;

        address issuanceToken = abi.decode(configData_, (address));
        setIssuanceToken(issuanceToken);
    }

    // =========================================================================
    // External Functions - Admin

    /**
     * @notice Adds a new destination for a specific chain
     * @param chainId_ The destination chain ID
     * @param destination_ The destination address on the target chain (Mailbox)
     * @param receiver_ The address to receive the message.
     */
    function addDestination(
        uint chainId_,
        address destination_,
        address receiver_
    ) external {
        require(destination_ != address(0), ERROR_INVALID_DESTINATION);
        _allowedDestinations[chainId_] = destination_;
        _receivers[chainId_] = receiver_;
        emit DestinationAdded(chainId_, destination_, receiver_);
    }

    /**
     * @notice Sets the issuance token address
     * @param issuanceToken_ The new issuance token address
     */
    function setIssuanceToken(address issuanceToken_) public {
        require(issuanceToken_ != address(0), ERROR_INVALID_ISSUANCE_TOKEN);
        _issuanceToken = issuanceToken_;
    }

    // =========================================================================
    // External Functions - User

    /**
     * @notice Bridges tokens to another chain
     * @param destinationChainId_ The destination chain ID
     * @param amount_ The amount of tokens to bridge
     */
    function bridge(uint32 destinationChainId_, uint amount_) external {
        require(
            _allowedDestinations[destinationChainId_] != address(0),
            ERROR_INVALID_DESTINATION
        );
        require(amount_ > 0, ERROR_INSUFFICIENT_AMOUNT);

        IERC20(_issuanceToken).safeTransferFrom(
            msg.sender, address(this), amount_
        );

        (address mailbox, address receiver) =
            getAllowedDestination(destinationChainId_);

        IMailbox(mailbox).dispatch(
            destinationChainId_,
            receiver.addressToBytes32(),
            TokenMessage.format(
                msg.sender.addressToBytes32(), amount_, "INVERTER_BRIDGE"
            )
        );

        emit TokensBridged(msg.sender, destinationChainId_, amount_);
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
     * @notice Gets the source chain ID
     * @return The source chain ID
     */
    function getSourceChainId() external view returns (uint) {
        return _sourceChainId;
    }

    /**
     * @notice Gets the allowed destination for a chain ID
     * @param chainId_ The chain ID to query
     * @return The allowed destination address (Mailbox) and the receiver address
     */
    function getAllowedDestination(uint chainId_)
        public
        view
        returns (address, address)
    {
        return (_allowedDestinations[chainId_], _receivers[chainId_]);
    }
}
