// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {VirtualSupplyTokenUpgradeable} from
    "src/modules/fundingManager/token/VirtualSupplyTokenUpgradeable.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {IVirtualSupplyToken} from
    "src/modules/fundingManager/token/IVirtualSupplyToken.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {PrimaryMarketMaker} from
    "src/modules/fundingManager/bondingCurve/PrimaryMarketMaker.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

contract BondingCurveFundingManager is
    IFundingManager,
    IVirtualSupplyToken,
    ContextUpgradeable,
    VirtualSupplyTokenUpgradeable,
    Module
{
    using Strings for uint;
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage
    PrimaryMarketMaker marketMaker;

    //--------------------------------------------------------------------------
    // Modifier

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        (
            bytes32 _name,
            bytes32 _symbol,
            uint _initialVirtualSupply,
            address _marketMaker
        ) = abi.decode(configdata, (bytes32, bytes32, uint, address));

        __VirtualSupplyToken_init(
            string(abi.encodePacked(_name)),
            string(abi.encodePacked(_symbol)),
            _initialVirtualSupply
        );

        marketMaker = PrimaryMarketMaker(_marketMaker);
    }

    function token() public view returns (IERC20) {
        return __Module_orchestrator.token();
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IVirtualSupplyToken
    function setVirtualSupply(uint _newSupply) public onlyAuthorizedOrManager {
        _setVirtualSupply(_newSupply);
    }

    function deposit(uint amount) external {
        // WIP
        // Add on/off functionality
        // Add optional fee
        marketMaker.buyOrder(amount);
    }

    function depositFor(address to, uint amount) external {
        // Add optional fee
    }

    function withdraw(uint amount) external {
        // WIP
        // Add on/off functionality
        // Add optional fee
        marketMaker.sellOrder(amount);
    }

    function withdrawTo(address to, uint amount) external {
        // Add on/off functionality
        // Add optional fee
    }

    function addCollateralToken(address _collateral)
        external
        onlyAuthorizedOrManager
    {
        marketMaker.addCollateralToken(_collateral);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    function transferOrchestratorToken(address to, uint amount)
        external
        onlyOrchestrator
    {
        __Module_orchestrator.token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }
}
