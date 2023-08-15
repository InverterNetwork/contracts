// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {RedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/RedeemingBondingCurveFundingManagerBase.sol";
import {BondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";
import {VirtualCollateralSupplyBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/VirtualCollateralSupplyBase.sol";
import {VirtualTokenSupplyBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/VirtualTokenSupplyBase.sol";
import {IBancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/IBancorFormula.sol";

// Internal Interfaces
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";
import {IVirtualTokenSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";
import {IVirtualCollateralSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualCollateralSupply.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

contract BancorVirtualSupplyBondingCurveFundingManager is
    VirtualTokenSupplyBase,
    VirtualCollateralSupplyBase,
    RedeemingBondingCurveFundingManagerBase
{
    //--------------------------------------------------------------------------
    // Storage
    IBancorFormula formula;

    //--------------------------------------------------------------------------
    // // Init Function

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        (
            bytes32 _name,
            bytes32 _symbol,
            uint8 _decimals,
            address _formula,
            uint _initalTokenSupply,
            uint _initialCollateralSupply
        ) = abi.decode(
            configData, (bytes32, bytes32, uint8, address, uint, uint)
        );

        __ERC20_init(
            string(abi.encodePacked(_name)), string(abi.encodePacked(_symbol))
        );

        formula = IBancorFormula(_formula);

        _setTokenDecimals(_decimals);
        _setVirtualCollateralSupply(_initialCollateralSupply);
        _setVirtualTokenSupply(_initalTokenSupply);
        _setCollateral(address(__Module_orchestrator.token()));
    }

    //--------------------------------------------------------------------------
    // Public Functions

    function buyOrder(uint _depositAmount)
        external
        payable
        override(BondingCurveFundingManagerBase)
    {
        // WiP
        // Deduct fee from incoming value. Fee is paid in collateral token
        uint amountIssued = _issueTokens(_depositAmount, collateral);
        _addTokenAmount(amountIssued);
        _addCollateralAmount(_depositAmount);
    }

    function sellOrder(uint _depositAmount)
        external
        payable
        override(RedeemingBondingCurveFundingManagerBase)
    {
        // WiP
        // Q: Deduct fee from token or collateral?
        uint redeemAmount = _redeemTokens(_depositAmount, collateral);
        _subTokenAmount(_depositAmount);
        _subCollateralAmount(redeemAmount);
    }

    //--------------------------------------------------------------------------
    // Restricted Functions

    function setVirtualTokenSupply(uint _virtualSupply)
        external
        override(VirtualTokenSupplyBase)
        onlyOrchestratorOwnerOrManager
    {
        _setVirtualTokenSupply(_virtualSupply);
    }

    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        override(VirtualCollateralSupplyBase)
        onlyOrchestratorOwnerOrManager
    {
        _setVirtualCollateralSupply(_virtualSupply);
    }

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    function _issueTokensFormulaWrapper(
        uint _depositAmount,
        address _collateral
    ) internal override(BondingCurveFundingManagerBase) returns (uint) {
        uint32 connectorWeight = 1000; // Mock value, needs to be calculated
        return formula.calculatePurchaseReturn(
            virtualTokenSupply,
            virtualCollateralSupply,
            connectorWeight,
            _depositAmount
        );
    }

    function _redeemTokensFormulaWrapper(
        uint _depositAmount,
        address _collateral
    )
        internal
        override(RedeemingBondingCurveFundingManagerBase)
        returns (uint)
    {
        uint32 connectorWeight = 1000; // Mock value, needs to be calculated
        return formula.calculateSaleReturn(
            virtualTokenSupply,
            virtualCollateralSupply,
            connectorWeight,
            _depositAmount
        );
    }
}
