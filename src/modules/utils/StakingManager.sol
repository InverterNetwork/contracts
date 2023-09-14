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
    // Storage
    uint private _totalAmount;

    mapping(address => LinkedIdList.List) private _stakeIds;
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
        returns (uint stakeId)
    {
        address sender = _msgSender();
        token.safeTransferFrom(sender, address(this), amount);
        //@todo create stake struct accordingly

        emit Deposit(stakeId, sender, address(this), amount);
    }

    function _withdrawTo(uint stakeId, address to, uint amount) internal {
        token.safeTransfer(to, amount);
        //@todo modify stake struct accordingly

        emit Withdrawal(stakeId, address(this), to, amount);
    }
}
