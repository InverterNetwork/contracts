// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IStakingManager} from "src/modules/utils/IStakingManager.sol";
// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract StakingManager is IStakingManager, Module {
    using SafeERC20 for IERC20;
    using LinkedIdList for LinkedIdList.List;

    IERC20 public token;
    //--------------------------------------------------------------------------
    // Modifiers

    modifier validAmount(uint amount) {
        if (amount == 0) {
            revert Module__StakingManager__InvalidAmount();
        }
        _;
    }

    modifier validStakeId(address addr, uint stakeId) {
        if (!_stakeIds[addr].isExistingId(stakeId)) {
            revert Module__StakingManager__InvalidStakeId();
        }
        _;
    }

    modifier validWithdrawAmount(address addr, uint stakeId, uint amount) {
        if (_stakeRegistry[addr][stakeId].amount < amount) {
            revert Module__StakingManager__InvalidWithdrawAmount();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage
    uint private _totalAmount;

    mapping(address => LinkedIdList.List) private _stakeIds;
    mapping(address => uint) private _stakeIdCounter;
    mapping(address => mapping(uint => Stake)) private _stakeRegistry;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        token = IERC20(abi.decode(configData, (address)));
    }

    //--------------------------------------------------------------------------
    // Functions

    //Getter Functions

    function getTotalAmount() external view returns (uint) {
        return _totalAmount;
    }

    function getStakeForAddress(address addr, uint id)
        external
        view
        returns (Stake memory stake)
    {
        return _stakeRegistry[addr][id];
    }

    function getAllStakeIdsForAddress(address addr)
        external
        view
        returns (uint[] memory stakeIds)
    {
        return _stakeIds[addr].listIds();
    }

    //Mutating Functions
    function deposit(uint amount) external returns (uint stakeId) {
        return _depositFor(_msgSender(), amount);
    }

    function depositFor(address to, uint amount)
        external
        returns (uint stakeId)
    {
        return _depositFor(to, amount);
    }

    function withdraw(uint stakeId, uint amount) external {
        _withdrawTo(stakeId, _msgSender(), amount);
    }

    function withdrawTo(uint stakeId, address to, uint amount) external {
        _withdrawTo(stakeId, to, amount);
    }

    function _depositFor(address to, uint amount)
        internal
        validAmount(amount)
        returns (uint stakeId)
    {
        //if no stakes have been created yet
        if (_stakeIdCounter[to] == 0) {
            //init LinkedList
            _stakeIds[to].init();
        }

        //Increase idCounter
        stakeId = ++_stakeIdCounter[to];
        //Add id to list
        _stakeIds[to].addId(stakeId);
        //Set Stake in registry
        _stakeRegistry[to][stakeId] =
            Stake({amount: amount, timesstamp: block.timestamp});

        address sender = _msgSender();
        token.safeTransferFrom(sender, address(this), amount);
        emit Deposit(stakeId, sender, address(this), amount);
    }

    function _withdrawTo(uint stakeId, address to, uint amount)
        internal
        validStakeId(_msgSender(), stakeId)
        validAmount(amount)
        validWithdrawAmount(_msgSender(), stakeId, amount)
    {
        address sender = _msgSender();
        Stake storage stake = _stakeRegistry[_msgSender()][stakeId];
        //If Stake amount equals amount user wants to withdraw
        if (amount == stake.amount) {
            //If full withdraw delete stake and remove it from list
            delete _stakeRegistry[sender][stakeId]; //@note this might even be not necessary

            _stakeIds[sender].removeId(
                _stakeIds[sender].getPreviousId(stakeId), //@note this is not ideal, but will do for the POC
                stakeId
            );
        } else {
            stake.amount -= amount;
        }

        token.safeTransfer(to, amount);
        emit Withdrawal(stakeId, address(this), to, amount);
    }
}
