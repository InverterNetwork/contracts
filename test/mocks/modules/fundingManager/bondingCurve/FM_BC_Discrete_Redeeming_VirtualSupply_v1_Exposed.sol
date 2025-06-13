// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
// Import the interface that defines ProtocolFeeCache
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";

// Access Mock of the FM_BC_Discrete_Redeeming_VirtualSupply_v1 contract for Testing.
contract FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed is
    FM_BC_Discrete_Redeeming_VirtualSupply_v1
{
    // Use the `exposed_` prefix for functions to expose internal functions for testing purposes only.

    function exposed_setIssuanceToken(address newIssuanceTokenAddress_)
        external
    {
        _setIssuanceToken(ERC20Issuance_v1(newIssuanceTokenAddress_));
    }

    function exposed_redeemTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _redeemTokensFormulaWrapper(_depositAmount);
    }

    function exposed_handleCollateralTokensAfterSell(
        address _receiver,
        uint _collateralTokenAmount
    ) external {
        _handleCollateralTokensAfterSell(_receiver, _collateralTokenAmount);
    }

    function exposed_handleCollateralTokensBeforeBuy(
        address _provider,
        uint _amount
    ) external {
        _handleCollateralTokensBeforeBuy(_provider, _amount);
    }

    function exposed_handleIssuanceTokensAfterBuy(
        address _receiver,
        uint _amount
    ) external {
        _handleIssuanceTokensAfterBuy(_receiver, _amount);
    }

    function exposed_issueTokensFormulaWrapper(uint _depositAmount)
        external
        view
        returns (uint)
    {
        return _issueTokensFormulaWrapper(_depositAmount);
    }

    function exposed_setSegments(PackedSegment[] memory newSegments_)
        external
    {
        _setSegments(newSegments_);
    }

    function exposed_setVirtualCollateralSupply(uint virtualSupply_) external {
        _setVirtualCollateralSupply(virtualSupply_);
    }

    function exposed_getProtocolFeeCache()
        external
        view
        returns (ProtocolFeeCache memory)
    {
        return _protocolFeeCache;
    }

    function exposed_setProtocolFeeCache(
        IFM_BC_Discrete_Redeeming_VirtualSupply_v1.ProtocolFeeCache memory
            newCache_
    ) external {
        _protocolFeeCache = newCache_;
    }

    function exposed_getFunctionFeesAndTreasuryAddresses(
        bytes4 functionSelector_
    )
        external
        view
        returns (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralFeeBps,
            uint issuanceFeeBps
        )
    {
        return _getFunctionFeesAndTreasuryAddresses(functionSelector_);
    }

    function exposed_getBuyFee() external view returns (uint) {
        return _getBuyFee();
    }

    function exposed_getSellFee() external view returns (uint) {
        return _getSellFee();
    }
}
