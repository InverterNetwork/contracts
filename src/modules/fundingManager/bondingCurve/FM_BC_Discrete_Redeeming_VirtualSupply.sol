// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IFundingManager_v1} from "../IFundingManager_v1.sol";
import {VirtualIssuanceSupplyBase_v1} from "./abstracts/VirtualIssuanceSupplyBase_v1.sol";
import {VirtualCollateralSupplyBase_v1} from "./abstracts/VirtualCollateralSupplyBase_v1.sol";
import {RedeemingBondingCurveBase_v1} from "./abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from "./abstracts/BondingCurveBase_v1.sol";
import {IBondingCurveBase_v1} from "./interfaces/IBondingCurveBase_v1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FM_BC_Discrete_Redeeming_VirtualSupply is
    IFundingManager_v1,
    VirtualIssuanceSupplyBase_v1,
    VirtualCollateralSupplyBase_v1,
    RedeemingBondingCurveBase_v1
{
    // Contract content will be added in subsequent steps

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(
            RedeemingBondingCurveBase_v1,
            VirtualCollateralSupplyBase_v1,
            VirtualIssuanceSupplyBase_v1
        )
        returns (bool)
    {
        revert("NOT IMPLEMENTED");
    }

    // IFundingManager_v1 implementations
    function token() external view returns (IERC20) {
        revert("NOT IMPLEMENTED");
    }

    function transferOrchestratorToken(address to, uint amount) external {
        revert("NOT IMPLEMENTED");
    }

    // VirtualIssuanceSupplyBase_v1 implementations
    function setVirtualIssuanceSupply(uint _virtualSupply) external virtual override {
        revert("NOT IMPLEMENTED");
    }

    // VirtualCollateralSupplyBase_v1 implementations
    function setVirtualCollateralSupply(uint _virtualSupply) external virtual override {
        revert("NOT IMPLEMENTED");
    }

    // RedeemingBondingCurveBase_v1 implementations
    function getStaticPriceForSelling() external view virtual override returns (uint) {
        revert("NOT IMPLEMENTED");
    }

    function _redeemTokensFormulaWrapper(uint _depositAmount) internal view virtual override returns (uint) {
        revert("NOT IMPLEMENTED");
    }

    function _handleCollateralTokensAfterSell(address _receiver, uint _collateralTokenAmount) internal virtual override {
        revert("NOT IMPLEMENTED");
    }

    // BondingCurveBase_v1 implementations (inherited via RedeemingBondingCurveBase_v1)
    function _handleCollateralTokensBeforeBuy(address _provider, uint _amount) internal virtual override {
        revert("NOT IMPLEMENTED");
    }

    function _handleIssuanceTokensAfterBuy(address _receiver, uint _amount) internal virtual override {
        revert("NOT IMPLEMENTED");
    }

    function _issueTokensFormulaWrapper(uint _depositAmount) internal view virtual override returns (uint) {
        revert("NOT IMPLEMENTED");
    }

    function getStaticPriceForBuying() external view virtual override(BondingCurveBase_v1, IBondingCurveBase_v1) returns (uint) {
        revert("NOT IMPLEMENTED");
    }
}
