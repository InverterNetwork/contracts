// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// External Imports
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract Mock_EverclearPayment {
    event IntentAdded(bytes32 intentId, uint queuePosition, Intent intent);

    uint public nonce;
    uint32 public DOMAIN;
    IntentStatus public nextIntentStatus;
    mapping(bytes32 => IntentStatus) public status;

    enum IntentStatus {
        NONE,
        ADDED,
        SETTLED,
        FAILED,
        SETTLED_AND_MANUALLY_EXECUTED
    }

    struct Intent {
        address initiator;
        address receiver;
        address inputAsset;
        address outputAsset;
        uint amount;
        uint24 maxFee;
        uint32 origin;
        uint32[] destinations;
        uint nonce;
        uint48 timestamp;
        uint48 ttl;
        bytes data;
    }

    function newIntent(
        uint32[] memory _destinations,
        address _to,
        address _inputAsset,
        address _outputAsset,
        uint _amount,
        uint24 _maxFee,
        uint48 _ttl,
        bytes calldata _data
    ) external returns (bytes32 _intentId) {
        // Increment nonce for each new intent
        nonce++;
        if (_maxFee == 333) {
            return bytes32(0);
        }
        //if data is the word "fail" intentional return bytes32(0)
        Intent memory _intent = Intent({
            initiator: msg.sender,
            receiver: _to,
            inputAsset: _inputAsset,
            outputAsset: _outputAsset,
            amount: _amount,
            maxFee: _maxFee,
            origin: DOMAIN,
            destinations: _destinations,
            nonce: nonce,
            timestamp: uint48(block.timestamp),
            ttl: _ttl,
            data: _data
        });

        // Generate a unique intent ID
        _intentId = keccak256(abi.encode(_intent));

        IERC20(_inputAsset).transferFrom(msg.sender, address(this), _amount);

        // // Set intent status to ADDED and emit the event
        status[_intentId] = IntentStatus.ADDED;
        emit IntentAdded(_intentId, nonce, _intent);

        return (_intentId);
    }

    function setNextIntentStatus(IntentStatus _status) external {
        nextIntentStatus = _status;
    }
}
